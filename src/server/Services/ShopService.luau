--!strict
--[[
	ShopService.lua — turning cash back into capability.

	THE APPLY STEP IS ONE LINE, AND THAT IS BY DESIGN, NOT BY ACCIDENT.
	Buying a tier is `data.gear[key] = next`. Nothing else. StatResolver.get() is
	recomputed from the profile every tick, and ToolService compares the held model's
	tier against the profile every third tick and re-equips on a mismatch. So the new
	detector is in your hands within about a third of a second with no event, no
	replication step and no cache to invalidate. ToolService's own comment says as
	much ("buying an upgrade changes what is in your hands the moment it lands") —
	written for a shop that did not exist yet.

	Resist the urge to add machinery here. Anything that fires an event on purchase
	is duplicating a path that already works.

	ANY TIER YOU CAN AFFORD, NOT JUST THE NEXT ONE. `buy()` used to only ever sell
	`currentTier + 1` — a player had to own every rung below the one they wanted.
	That is gone: `buy()` takes a tier number and sells THAT tier directly, for
	exactly its own listed price, as long as it is not already owned. Skipping from
	Bent Coil straight to The Oracle costs The Oracle's price and nothing else — there
	is no toll for the rungs you walked past.

	AND YOU OWN WHAT YOU BOUGHT, NOTHING ELSE. Skipping used to grant the rungs it
	skipped as a side effect rather than as a decision: ownership WAS the equipped
	tier, and the shop asked `tier <= currentTier`, so paying for The Oracle reported
	six detectors the player never bought as owned. The profile carries a real set now
	(`gearOwned`, DataService's TEMPLATE), and the two facts that used to be one number
	are two:

	    data.gear[track]       what is IN YOUR HANDS. StatResolver reads it,
	                           ToolService polls it. Unchanged by all of this.
	    data.gearOwned[track]  the tiers you actually paid for, ascending.

	So a skipped rung stays on the shelf at its own price forever, and `buyTier`
	refuses only what you already own rather than everything at or below you.

	WHICH MAKES EQUIPPING A REAL VERB — `equipTier`, and the only other thing in the
	codebase that writes `gear[track]`. Owning a set you cannot choose from would be a
	trap: buying a lighter detector on purpose would take your good one away with no
	way back. An owned tier's panel card is an EQUIP button and its rack hook's E
	switches to it instead of charging you again, so dropping down a rung and climbing
	back is one press each way.

	`offerFor` returns a `tiers` catalog — every tier of the track, worst first, each
	tagged owned/current/buyable/equippable/affordable — so the panel can draw all of
	them with the right verb on each. `buyable` means "not owned", `equippable` means
	"owned but not in your hands"; see `CatalogEntry` below.

	THERE ARE TWO DOORS ONTO buyTier NOW, AND ONLY ONE OF THEM IS THE PANEL.
	Every tier of the three tool tracks also hangs on a rail beside its shop's stand
	with its own ProximityPrompt (build/Shops' rack), so a player who knows which
	detector they want walks up to that detector and presses E — no panel, no card,
	no row to find. `wireUpgrade` below is that path. It lands on exactly the same
	`buyTier` the panel's Buy button does, with the same validation, so nothing about
	what a purchase COSTS or whether it is legal depends on which door it came
	through. The panel is still there and still opens; see build/Shops' header for
	why both are worth keeping.

	THE CLIENT IS NEVER TRUSTED ABOUT WHERE IT IS STANDING, OR WHAT THINGS COST.
	The buy request carries a track name and a tier number, and neither is trusted on
	its own. The server independently asks StationService which shop this player is
	actually at and refuses if it is not the one they claim; the tier is checked
	against that track's own length and against what the player already owns; and the
	price is read back out of Gear.tier(), never out of the request. A crafted remote
	call from anywhere on the map, naming any tier, buys nothing but what a real click
	at that shop could have bought — the same shape of guard DeconService already
	applies to sell and scrub.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)

local ShopService = {}

local resultRemote: any = nil

--- One rung of the ladder, as the shop panel draws it.
---
--- `buyable` IS `not owned` — every tier you have not bought, all at once, each
--- gated only by its OWN price. There is no "buy them in order" rule to encode; the
--- panel shows every unowned tier as a live purchase button rather than a preview of
--- what comes next.
---
--- OWNERSHIP IS A SET AND `current` IS A SEPARATE QUESTION. `owned` used to mean
--- `tier <= currentTier`, so buying The Oracle from Bent Coil reported six detectors
--- you never bought as owned. It reads the profile's real `gearOwned` list now, and
--- what you are HOLDING is `gear[track]`, which is a tier you own and choose. The two
--- were one number and are two now, which is what makes `equippable` possible at all.
export type CatalogEntry = {
	tier: number,
	name: string,
	price: number,
	stats: { string },
	owned: boolean, -- in gearOwned: you bought it (or started with it)
	current: boolean, -- gear[track]: what is in your hands right now
	buyable: boolean, -- not owned, purchasable on its own at its own price
	equippable: boolean, -- owned but not current: yours, and you can switch to it
	affordable: boolean, -- buyable AND you have the cash for THIS tier's price
}

export type Offer = {
	track: string,
	maxed: boolean, -- you own every tier of this track; nothing left to buy
	tiers: { CatalogEntry },
}

local function isTrack(track: string?): boolean
	if track == nil then
		return false
	end
	for _, known in Gear.TRACKS do
		if known == track then
			return true
		end
	end
	return false
end

--- 0.9970 and 0.9988 are two different suits; "1.00" and "1.00" are not. Suit
--- `reduction` is the one stat whose whole ladder lives in the fourth decimal, so
--- format wide and trim the trailing zeros rather than picking a fixed precision
--- that flattens it.
local function num(value: number): string
	if value % 1 == 0 then
		return tostring(value)
	end
	local s = string.format("%.4f", value)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

--- `pullSpeed` is a field name; "pull speed" is a label. The catalog is read by a
--- player, not by whoever wrote Config/Gear.
local function pretty(key: string): string
	local spaced = string.gsub(key, "(%l)(%u)", "%1 %2")
	return string.lower(spaced)
end

--- Everything this tier IS, rather than what it adds. Absolute stats on every card
--- so the ladder can be read across — deltas describe one step and are useless for
--- comparing rung 2 against rung 7 at a glance.
local function statLines(def: any): { string }
	local lines = {}
	for key, value in def do
		if key == "name" or key == "price" then
			continue
		end
		if type(value) == "number" then
			table.insert(lines, `{pretty(key)} {num(value)}`)
		elseif type(value) == "boolean" and value then
			table.insert(lines, pretty(key))
		end
	end
	table.sort(lines)
	return lines
end

-- ── Ownership ─────────────────────────────────────────────────────────
--
-- WHAT YOU OWN AND WHAT YOU HOLD ARE TWO DIFFERENT FACTS NOW. They used to be one
-- number: `gear.detector = 6` meant both "your detector is a Resonance Mapper" and
-- "you own tiers 1 through 6". That second reading is what made buying the top of a
-- track hand you every rung under it, which is a claim the player never paid for.
--
--   data.gear[key]       the EQUIPPED tier. StatResolver reads it, ToolService polls
--                        it and re-equips on a mismatch. Unchanged, deliberately.
--   data.gearOwned[key]  an ascending array of the tiers you actually bought.
--
-- The array (rather than a `{[6] = true}` set) is forced by DataService's TEMPLATE
-- note: no gaps in numeric arrays, no mixed key types. A track is at most 8 rungs, so
-- every operation here is a linear scan and none of it is worth indexing.
--
-- DataService.backfillGearOwned guarantees the per-track array exists from the moment
-- a profile loads, so these never have to create one. They tolerate a missing array
-- anyway — a nil here would otherwise turn "your save is oddly shaped" into "you own
-- nothing", which would offer to re-sell a player their own gear.

local function ownedTiers(data: any, track: string): { number }
	local key = Gear.profileKey(track)
	local list = if data.gearOwned then data.gearOwned[key] else nil
	return if type(list) == "table" then list else {}
end

local function ownsTier(data: any, track: string, tier: number): boolean
	for _, owned in ownedTiers(data, track) do
		if owned == tier then
			return true
		end
	end
	return false
end

--- Record a tier as bought. Ascending and duplicate-free, because the array is what
--- gets written to the DataStore and a shop that inserted twice would grow it without
--- bound over a long-lived save.
local function grantTier(data: any, track: string, tier: number)
	if ownsTier(data, track, tier) then
		return
	end
	local key = Gear.profileKey(track)
	if data.gearOwned == nil then
		data.gearOwned = {}
	end
	local list = data.gearOwned[key]
	if type(list) ~= "table" then
		list = {}
		data.gearOwned[key] = list
	end
	table.insert(list, tier)
	table.sort(list)
end

--- Every tier of `track`, worst first, tagged with where the player sits on it.
---
--- Worst-first needs no sorting: Config/Gear already lists each track in ascending
--- tier order, and `Gear.tier(track, n)` indexes that list directly. If a track is
--- ever reordered there, this comes out reordered too — which is correct, since the
--- tier NUMBER is the thing the profile stores.
local function catalogFor(data: any, track: string): { CatalogEntry }
	local equipped = data.gear[Gear.profileKey(track)] or 1
	local entries = {}

	for tier = 1, Gear.maxTier(track) do
		local def = Gear.tier(track, tier)
		local owned = ownsTier(data, track, tier)
		local current = tier == equipped
		local buyable = not owned
		table.insert(entries, {
			tier = tier,
			name = def.name,
			price = def.price,
			stats = statLines(def),
			owned = owned,
			current = current,
			buyable = buyable,
			-- Owned but not in your hands: the one state the old model could not
			-- represent, and the reason this catalog carries five flags rather than
			-- four. The panel draws it as a live EQUIP button where it used to draw
			-- dead greyed chrome.
			equippable = owned and not current,
			affordable = buyable and data.cash >= def.price,
		})
	end

	return entries
end

--- Pure. Safe to call every tick to drive the panel.
function ShopService.offerFor(data: any, track: string): Offer?
	if not isTrack(track) or data == nil then
		return nil
	end

	local tiers = catalogFor(data, track)

	-- MAXED IS "NOTHING LEFT TO BUY", not "you are standing on the top rung". Those
	-- were the same sentence while ownership was a high-water mark; with a set, a
	-- player holding The Oracle can still have six unbought rungs behind them, and
	-- telling them the shop is finished with them would be a lie.
	local maxed = true
	for _, entry in tiers do
		if entry.buyable then
			maxed = false
			break
		end
	end

	return {
		track = track,
		maxed = maxed,
		tiers = tiers,
	}
end

--- Buy a SPECIFIC tier of `track`, not necessarily the next one. Returns (ok,
--- message) like EconomyService.sell.
---
--- `tier` is the one number in this request that used to not exist — `buy()` used
--- to infer it as `currentTier + 1` and there was nothing else it could be. Now the
--- client says which card it clicked, so this validates that number the same way any
--- other player-supplied value gets validated at a boundary: a real tier of THIS
--- track, and not one already owned. Neither check is a security boundary on its
--- own — the price still comes from Gear.tier(track, tier), server-side, never from
--- the request — they exist so a malformed tier fails with a message instead of
--- indexing past the end of the array or silently re-selling something you own.
--- The purchase itself, with NO opinion about where the player is standing.
---
--- Split out of `buy` when the Luck track moved from a shop counter to a button
--- with a ProximityPrompt on it (build/Plots.buildLuckButton). Everything that makes a
--- purchase safe is in here — the track is checked against Gear.TRACKS before it can
--- index anything, the tier against that track's own length and against what you
--- already own, and the price is read back out of Gear.tier() and never taken from a
--- caller. What is NOT in here is the proximity check, because the two call sites
--- prove proximity in genuinely different ways:
---
---   buy()            a client sent a request naming a shop, so the server has to
---                    re-derive the player's position itself and refuse a mismatch.
---   the sign prompt  ProximityPrompt.Triggered fires ON THE SERVER, and Roblox
---                    enforces MaxActivationDistance before it ever fires. The
---                    proximity is not a claim to be checked; it is a precondition
---                    the engine already established.
---
--- That is why the sign can skip StationService entirely and the counters cannot.
function ShopService.buyTier(player: Player, track: string, tier: number?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	-- Reject anything that is not a real track before it can index a table.
	if not isTrack(track) then
		return false, "no such shop"
	end

	local maxTier = Gear.maxTier(track)
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > maxTier then
		return false, "no such tier"
	end

	-- OWNERSHIP, NOT ALTITUDE. This was `tier <= currentTier`, which refused any rung
	-- at or below the one you were holding — and that test is exactly what made buying
	-- the top of a track swallow everything under it. A tier you skipped past is still
	-- for sale, and the only thing that can stop the sale is having bought it before.
	local key = Gear.profileKey(track)
	if ownsTier(data, track, tier) then
		return false, "you already own that one"
	end

	local def = Gear.tier(track, tier)

	-- Debit first, at THIS tier's own price — not the sum of what it skipped past.
	-- If this fails nothing else has happened yet, so there is no half-applied
	-- purchase to unwind.
	local paid, reason = EconomyService.spend(player, def.price)
	if not paid then
		return false, reason
	end

	grantTier(data, track, tier)

	-- BUYING EQUIPS, EVEN DOWNWARD. You went to a shop and paid for a specific tool,
	-- so putting it in your hands is the least surprising thing that can happen — and
	-- with the equip path below, a deliberate buy of a lower rung is switchable back
	-- in one press rather than being a trap you cannot undo.
	data.gear[key] = tier

	-- THE PURCHASE HAS TO LAND SOMEWHERE THE PLAYER CAN SEE. Five of the six tracks
	-- land on the player: a detector or a magnet appears in their hands the next time
	-- ToolService looks at them, and a suit, boots or satchel is felt rather than seen.
	-- The Cleaner track lands on their BASE — it is the monitor bolted to the mast at
	-- their own cleansing station (build/Plots.buildHoseRig) — so it needs a poke, the
	-- same way a Luck purchase needs one to repaint its button. Which plot, and what a
	-- plot looks like, is ExhibitService's business and not this file's.
	if track == "Cleaner" then
		ExhibitService.refreshHose(player)
	end

	return true, `bought {def.name} for ${def.price}`
end

--- Hold a tier you already own. The other half of the set model: `buyTier` decides
--- what is YOURS, this decides what is IN YOUR HANDS, and nothing else writes
--- `gear[track]` except the debug console.
---
--- It costs nothing and takes nothing, so the only thing to validate is that the tier
--- is real and that the player actually owns it — the ownership check is the whole
--- security boundary here, since a client that could equip anything could equip The
--- Oracle for free. Same no-proximity split as `buyTier`: see its header.
function ShopService.equipTier(player: Player, track: string, tier: number?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	if not isTrack(track) then
		return false, "no such shop"
	end

	local maxTier = Gear.maxTier(track)
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > maxTier then
		return false, "no such tier"
	end

	if not ownsTier(data, track, tier) then
		return false, "you don't own that one"
	end

	local key = Gear.profileKey(track)
	if data.gear[key] == tier then
		return false, "already in your hands"
	end

	-- ToolService polls this field and swaps the held model on a mismatch, so for the
	-- five tracks you HOLD this one write is the entire equip.
	data.gear[key] = tier

	-- THE SIXTH TRACK IS NOT HELD, so nothing polls it into existence. The Cleaner rung
	-- is the machine bolted to the mast at your own wash bay, and the only thing that
	-- moves it is this poke (see buyTier's note). Without it, equipping a lower rung you
	-- already own would leave the bay SHOWING one hose while CLEANING at another --
	-- silent, and exactly the sort of thing that only turns up as "the shop is lying".
	if track == "Cleaner" then
		ExhibitService.refreshHose(player)
	end

	return true, `equipped {Gear.tier(track, tier).name}`
end

--- The luck button's own purchase path — not a tier lookup, because Luck no longer
--- has tiers to look up (Config/Gear.luau's header above `Gear.luckMultiplier`
--- explains why). Same shape as `buyTier` otherwise: debit first, at the price for
--- the level the player is CURRENTLY at, and only mutate the profile once the debit
--- lands, so a failed purchase leaves nothing half-applied to unwind.
function ShopService.buyLuck(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local level = data.gear.luck or 1
	local price = Gear.luckPrice(level)

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	data.gear.luck = level + 1
	return true, string.format("Luck -> %.1fx (paid $%d)", Gear.luckMultiplier(data.gear.luck), price)
end

function ShopService.buy(player: Player, track: string, tier: number?): (boolean, string)
	-- THE CLIENT IS NEVER TRUSTED ABOUT WHERE IT IS STANDING. The request names a
	-- shop; the server independently asks StationService which shop this player is
	-- actually at and refuses if it is not the one they claim. Everything else about
	-- the purchase lives in buyTier.
	if not isTrack(track) then
		return false, "no such shop"
	end
	local kind = StationService.kindOf(player)
	local id = StationService.idOf(player)
	if kind ~= "shop" or id ~= track then
		return false, "you aren't at that shop"
	end

	return ShopService.buyTier(player, track, tier)
end

--- `equipTier` with the same standing-there check `buy` does, for the same reason:
--- the request names a shop and the server re-derives where the player actually is.
--- Switching gear is free, so this is not guarding a wallet — it is keeping the shop
--- a PLACE. Being able to re-equip from anywhere on the map would quietly turn the
--- panel into a loadout menu you never have to walk to.
function ShopService.equip(player: Player, track: string, tier: number?): (boolean, string)
	if not isTrack(track) then
		return false, "no such shop"
	end
	local kind = StationService.kindOf(player)
	local id = StationService.idOf(player)
	if kind ~= "shop" or id ~= track then
		return false, "you aren't at that shop"
	end

	return ShopService.equipTier(player, track, tier)
end

-- ── Upgrade signs ─────────────────────────────────────────────────────

--- Matches Kit.UPGRADE_TAG. Hardcoded rather than required, for the same reason
--- Tuning.AURA_TAG is: build/Kit lives in ServerScriptService and this is a service,
--- so a require would work today and stop working the moment anything client-side
--- needs the same string. One name, two places, and World.verify() asserts they agree.
local UPGRADE_TAG = "Upgrade"

--- Wire one world object that sells a track by proximity instead of by panel.
---
--- The prompt is created by the BUILDER (build/Plots.buildLuckButton for Luck, or
--- build/Shops' rack hooks for a tiered track) and saved with the place; this
--- connects behaviour to it at boot. Splitting it that way is the same split every
--- station already uses — geometry and attributes are build-time, behaviour is
--- runtime — and it is what lets a shop be rebuilt without touching a service.
---
--- TWO SHAPES OF SELLER COME THROUGH HERE, told apart by `SellsTier`:
---
---   SellsTrack only ............. Luck's button. No ladder to index, so it takes
---                                 buyLuck's own path — Config/Gear's header above
---                                 `luckMultiplier` says why Luck has no tiers.
---   SellsTrack + SellsTier ...... one hook on a shop rack: THIS rung of that track.
---                                 Straight to buyTier, the same call the panel's
---                                 Buy button lands on.
---
--- NEITHER PATH CHECKS PROXIMITY, and that is not an omission — see buyTier's own
--- header. ProximityPrompt.Triggered fires on the SERVER and Roblox enforces
--- MaxActivationDistance before it ever fires, so the player's position is a
--- precondition the engine established rather than a claim to re-derive. The panel's
--- `buy()` has to do that work because a client sent it a request; a prompt does not.
local function wireUpgrade(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local track = part:GetAttribute("SellsTrack")
	if type(track) ~= "string" then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		warn(`[shop] {part:GetFullName()} sells "{track}" but has no ProximityPrompt — nobody can buy from it`)
		return
	end

	-- Read ONCE, at wiring time, not inside the handler. A rack hook's tier is
	-- geometry — it is which hook this is — and re-reading it per trigger would make
	-- the price a player pays depend on an attribute that anything could have moved
	-- since. buyTier re-validates it against the track's length regardless.
	local tier = part:GetAttribute("SellsTier")
	local sellsTier = if type(tier) == "number" then tier else nil

	if sellsTier == nil and track ~= "Luck" then
		warn(`[shop] {part:GetFullName()} sells "{track}" with no SellsTier — only Luck may omit it`)
		return
	end

	prompt.Triggered:Connect(function(player: Player)
		local ok: boolean, message: string
		if sellsTier ~= nil then
			-- ONE HOOK, TWO VERBS, DECIDED HERE RATHER THAN BY THE CLIENT. Pressing E
			-- on a tool you already own equips it; on one you don't, it buys it. The
			-- prompt is a single shared instance and cannot say different things to
			-- two players, so the client repaints its ActionText locally off the same
			-- offer that paints the price cards (StationController's rack pass) — but
			-- what the press DOES is decided from the profile, right here, and never
			-- from what that player's screen happened to say.
			local data = DataService.data(player)
			if data ~= nil and ownsTier(data, track, sellsTier) then
				ok, message = ShopService.equipTier(player, track, sellsTier)
			else
				ok, message = ShopService.buyTier(player, track, sellsTier)
			end
		else
			ok, message = ShopService.buyLuck(player)
		end
		resultRemote:FireClient(player, message)
		if ok then
			print(`[shop] {player.Name}: {message}`)
			if sellsTier == nil then
				-- The luck button's own billboard names the buyer's multiplier, not a
				-- shop panel that isn't there — see ExhibitService.refreshLuck's header
				-- for why that lives in ExhibitService rather than here. A rack hook has
				-- nothing to refresh: its card is world geometry showing a fixed price,
				-- and the per-player owned-check over it is drawn client-side off the
				-- offer the panel is already receiving (StationController's rack pass).
				ExhibitService.refreshLuck(player)
			end
		end
	end)
end

function ShopService.init()
	resultRemote = Net.get("StationResult")
end

function ShopService.start()
	-- Tag-indexed rather than a Workspace walk, and it covers signs that appear LATER:
	-- World.rebuild() can be run from the command bar mid-session, and a sign built
	-- then would otherwise sit there inert until the next server start.
	for _, part in CollectionService:GetTagged(UPGRADE_TAG) do
		wireUpgrade(part)
	end
	CollectionService:GetInstanceAddedSignal(UPGRADE_TAG):Connect(wireUpgrade)
end

return ShopService
