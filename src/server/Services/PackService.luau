--!strict
--[[
	PackService.luau — the Starter Pack and the Pro Pack (Config/Packs).

	A pack is a bundle of grants the game already has, run in one receipt step through
	ProductService: cash (EconomyService.award), crates straight into the bag even past
	capacity (CrateService.give, the Mystery crates' rule), Lucky Clover time
	(LuckBoostService.grant) and 2x cash time (CashBoostService.grant). Every one of them
	only mutates `data` and never yields, which is what makes the whole pack land, or not
	land, as one.

	OWNERSHIP is `data.packs[key] = true`, mirrored to a Player attribute (Packs.attr) on
	join and on purchase, so the Shop card can say OWNED without a remote. A repeat
	receipt still grants -- see Config/Packs' header.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packs = require(ReplicatedStorage.Shared.Config.Packs)

local DataService = require(script.Parent.DataService)
local ProductService = require(script.Parent.ProductService)
local EconomyService = require(script.Parent.EconomyService)
local CrateService = require(script.Parent.CrateService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local CashBoostService = require(script.Parent.CashBoostService)

local PackService = {}

local function mirror(player: Player, data: any)
	for _, pack in Packs.PACKS do
		player:SetAttribute(Packs.attr(pack.key), Packs.owns(data, pack.key))
	end
end

--- Everything in `pack`, onto this player. Mutates `data` and never yields
--- (ProductService's contract); the bag notice waits until the receipt step is done.
function PackService.grant(player: Player, data: any, pack: Packs.Pack)
	if Packs.owns(data, pack.key) then
		warn(`[pack] {player.Name} bought {pack.name} again -- granting it, they paid`)
	end
	if pack.cash > 0 then
		EconomyService.award(player, pack.cash, "robux")
	end
	for _, crateId in pack.crates do
		CrateService.give(data, crateId)
	end
	if pack.luckSeconds > 0 then
		LuckBoostService.grant(player, data, pack.luckSeconds)
	end
	if pack.cashBoostSeconds > 0 then
		CashBoostService.grant(player, data, pack.cashBoostSeconds)
	end
	data.packs = data.packs or {}
	data.packs[pack.key] = true
	player:SetAttribute(Packs.attr(pack.key), true)
	task.defer(CrateService.notify, player, `{pack.name} unlocked! {#pack.crates} crates added to your bag`)
end

--- Clear a pack's ownership (DebugService's /pack off), so the card can be bought again.
function PackService.clear(player: Player, data: any, key: string)
	if data.packs then
		data.packs[key] = nil
	end
	player:SetAttribute(Packs.attr(key), false)
end

function PackService.init()
	-- In init, not start, so no receipt can land before these are registered.
	for _, pack in Packs.PACKS do
		ProductService.register(pack.id, function(player, data)
			PackService.grant(player, data, pack)
		end)
	end
end

function PackService.start()
	DataService.onLoaded(mirror)
end

return PackService
