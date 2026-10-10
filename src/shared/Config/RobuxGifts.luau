--!strict
--[[
	RobuxGifts.luau — the Robux developer products a player can buy FOR someone else.

	A gift is the same developer product as buying it for yourself, with the same id,
	price and grant. Nothing new goes on the dashboard. Pressing the purple gift button
	asks the server to remember who it is for (the buyer's `data.giftIntent`), and the
	server opens the normal purchase prompt. When the receipt arrives, ProductService
	sees the intent and sends the grant to the recipient through a ProfileStore
	message, not to the buyer. See Services/RobuxGiftService.

	ANYONE WHO HAS PLAYED CAN RECEIVE A GIFT, online or not. An online recipient gets it
	straight away. Otherwise it waits in their save's message queue until their next
	join. Each delivery carries the receipt's PurchaseId, so a resend can never grant
	twice.

	GAME PASSES ARE NOT HERE. Roblox only sells a pass to the player who owns it, so
	gifting one would need its own developer product per pass (the user's call, 2026-10-08:
	not for now). Gear tiers are not here either, since they depend
	on what the buyer already owns. Neither is the Server Luck Boost, which already
	benefits everyone in the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local CrateShop = require(Config.CrateShop)
local Crates = require(Config.Crates)
local LuckBoost = require(Config.LuckBoost)
local Packs = require(Config.Packs)
local ShopProducts = require(Config.ShopProducts)

local RobuxGifts = {}

export type Gift = {
	id: number,
	name: string, -- as the recipient's popup says it: "Lucky Clover", "$500K Cash"
	pack: string?, -- a Config/Packs key: once per player, so refused for someone who owns it
}

--- How long a pressed gift button keeps its recipient. A receipt that arrives later
--- than this goes to the buyer, as a normal purchase would. That covers a prompt whose
--- "closed" never arrived and a gift the buyer forgot about.
RobuxGifts.INTENT_SECONDS = 15 * 60
--- Seconds between one buyer's gift requests. Each one makes web calls (the name
--- lookup and the recipient's save).
RobuxGifts.REQUEST_COOLDOWN = 2
--- Roblox usernames are 3-20 characters.
RobuxGifts.NAME_MAX = 20

local GIFTS: { Gift } = {}
local byId: { [number]: Gift } = {}

local function add(gift: Gift)
	if gift.id == 0 or byId[gift.id] then
		return
	end
	byId[gift.id] = gift
	table.insert(GIFTS, gift)
end

add({ id = LuckBoost.PRODUCT_ID, name = `Lucky Clover ({math.floor(LuckBoost.PRODUCT_SECONDS / 60)} min 2x luck)` })
for _, pack in Packs.PACKS do
	add({ id = pack.id, name = pack.name, pack = pack.key })
end
for _, pack in ShopProducts.CASH do
	add({ id = pack.id, name = `{pack.label} Cash` })
end
for _, pack in ShopProducts.SPEED do
	add({ id = pack.id, name = `{pack.label} Walk Speed` })
end
for _, pad in CrateShop.PADS do
	for _, offer in pad.offers do
		local productId = offer.productId
		if productId and productId ~= 0 and Crates.has(offer.crateId) then
			add({ id = productId, name = Crates.get(offer.crateId).name })
		end
	end
end

RobuxGifts.GIFTS = GIFTS

--- The giftable product with this id, or nil.
function RobuxGifts.get(productId: number): Gift?
	return byId[productId]
end

return RobuxGifts
