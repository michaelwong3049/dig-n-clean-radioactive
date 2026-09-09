--!strict
--[[
	IdentifyService.lua — the moment a "???" becomes a thing with a name.

	WHAT YOU DIG UP IS A LUMP OF SLAG (Shared/ItemCrust). It goes in the bag as "???",
	it sits in your hand as a rock, and the ONE thing anybody knows about it is the
	rarity the detector read on the way in. Taking the crust off is what turns it into
	an item — that is the point of the wash bay now, and this file is the single place
	that moment is allowed to happen.

	THREE WAYS TO LEARN WHAT YOU HAVE, and all three come through here:

	  1. YOU CLEAN IT.        WashService, when the last patch pops. The intended one.
	  2. YOU SELL IT BLIND.   EconomyService, at 20% (Tuning.DIRTY_SELL_MULTIPLIER).
	                          The trader tells you what it was as he takes it — which is
	                          the gamble: cash now, or the hose and the full price.
	  3. IT NEEDED NO CLEAN.  DigService, for a Prewar Sealed pull. It came out of the
	                          ground in its packaging, so there was never a mystery.

	WHY THIS IS NOT JUST A LINE IN EACH OF THOSE FILES. `data.discovered` is the index,
	and the index is a spoiler surface: it used to be written in `unearth`, which meant
	the catalogue tile for a Gold Ring lit up the instant one broke the surface, some
	minutes before the player was supposed to find out they had a Gold Ring. Moving the
	write to "you actually know what this is" is the whole fix, and it only stays fixed
	if there is one function to move it to.

	MARKING AND ANNOUNCING ARE SEPARATE ON PURPOSE. The wash bay hides every
	LayerCollector while you are in the first-person view (WashController), so the
	banner has to wait until the session has handed the screen back — but the profile
	write must NOT wait, or a player who disconnects during the reveal beat comes back
	holding a clean item their index has never heard of. `identify` writes; `announce`
	shows; the wash calls them a second apart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local IdentifyService = {}

local identifiedRemote: any = nil

--- Write it into the index. Returns whether this was the FIRST of its kind, so the
--- announcement can say so — a first find is the only reason to look at the banner
--- twice.
function IdentifyService.identify(player: Player, item: any): boolean
	local data = DataService.data(player)
	if data == nil or item == nil or item.itemId == nil then
		return false
	end

	local first = data.discovered[item.itemId] ~= true
	data.discovered[item.itemId] = true
	return first
end

--- Put it on screen. Same shape as the Unearthed payload, because it lands in the same
--- banner (client DetectorController) — one renderer, two moments.
function IdentifyService.announce(player: Player, item: any, firstFind: boolean)
	if identifiedRemote == nil or item == nil then
		return
	end
	local def = Items.get(item.itemId)
	identifiedRemote:FireClient(player, {
		itemId = def.id,
		name = def.name,
		flavor = def.flavor,
		rarity = item.rarity,
		modifier = item.modifier,
		weight = def.weight,
		firstFind = firstFind,
	})
end

--- Both halves, for the callers with nothing to wait for.
function IdentifyService.reveal(player: Player, item: any)
	IdentifyService.announce(player, item, IdentifyService.identify(player, item))
end

function IdentifyService.init()
	identifiedRemote = Net.get("ItemIdentified")
end

return IdentifyService
