--!strict
--[[
	RobuxGiftService.luau — buying a Robux product for someone else (Config/RobuxGifts).

	1. THE ASK. The purple gift button sends RobuxGift("send", productId, recipient).
	   The recipient is a UserId (from the server list) or a typed username. We look
	   them up, refuse yourself, anyone who has never played and a once-only pack they
	   already own, then save the buyer's intent (`data.giftIntent`: product,
	   recipient, time) and open Roblox's purchase prompt from here.
	2. THE RECEIPT. ProductService asks `find` whether the receipt is a gift. If it is,
	   `send` queues a message on the recipient's save (DataService.message, which
	   works online or not) with the receipt's PurchaseId, and the buyer is told the
	   gift is on its way.
	3. THE DELIVERY. Every loaded profile has a message handler. A gift message runs
	   that product's own ProductService grant on the RECIPIENT, records
	   "gift:<PurchaseId>" in their `receipts` (so a resent copy grants nothing; the
	   prefix keeps it apart from the buyer's own record of the same id), marks the
	   message processed and saves. They get a "<name> gifted you <item>!" popup.

	The intent expires after RobuxGifts.INTENT_SECONDS. It is also cleared when the
	prompt closes without a purchase, and when the buyer presses a plain BUY ("clear"),
	so a later purchase for themselves never goes to someone else.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Packs = require(Shared.Config.Packs)
local RobuxGifts = require(Shared.Config.RobuxGifts)

local DataService = require(script.Parent.DataService)
local ProductService = require(script.Parent.ProductService)
local SfxService = require(script.Parent.SfxService)

local RobuxGiftService = {}

local MESSAGE_KIND = "robuxGift"
-- A gift opened right at join waits this long after the player arrived before its
-- popup, so the client is listening by then.
local JOIN_SETTLE = 8

local remote: RemoteEvent = nil
local lastAsk: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local joinedAt: { [Player]: number } = {}

local function reply(player: Player, productId: number, ok: boolean, message: string)
	if player.Parent then
		remote:FireClient(player, { kind = "result", productId = productId, ok = ok, message = message })
	end
end

local function itemName(productId: number): string
	local gift = RobuxGifts.get(productId)
	return if gift then gift.name else "a gift"
end

--- (userId, username) for a picked UserId or a typed username, or nil.
local function resolve(recipient: any): (number?, string?)
	if type(recipient) == "number" then
		if recipient ~= recipient or recipient <= 0 or recipient % 1 ~= 0 then
			return nil, nil
		end
		local here = Players:GetPlayerByUserId(recipient)
		if here then
			return here.UserId, here.Name
		end
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, recipient)
		if ok and type(name) == "string" then
			return recipient, name
		end
		return nil, nil
	end
	if type(recipient) ~= "string" or #recipient > 40 then
		return nil, nil
	end
	local name = string.match(recipient, "^%s*@?([%w_]+)%s*$")
	if name == nil or #name < 3 or #name > RobuxGifts.NAME_MAX then
		return nil, nil
	end
	for _, other in Players:GetPlayers() do
		if string.lower(other.Name) == string.lower(name) then
			return other.UserId, other.Name
		end
	end
	local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, name)
	if not ok or type(userId) ~= "number" then
		return nil, nil
	end
	-- The name as Roblox spells it, not as it was typed.
	local okName, real = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return userId, if okName and type(real) == "string" then real else name
end

local function ask(player: Player, productId: number, recipient: any)
	local gift = RobuxGifts.get(productId)
	if gift == nil then
		reply(player, productId, false, "That can't be gifted")
		return
	end
	if DataService.data(player) == nil then
		return
	end

	local userId, name = resolve(recipient)
	if userId == nil or name == nil then
		reply(player, productId, false, "Couldn't find that player")
		return
	end
	if userId == player.UserId then
		reply(player, productId, false, "That's you! Use BUY instead")
		return
	end
	-- Their live save if they're here, or the saved copy if not.
	local here = Players:GetPlayerByUserId(userId)
	local theirs = if here then DataService.data(here) else nil
	if theirs == nil then
		local ok, saved = DataService.peek(userId)
		if not ok then
			reply(player, productId, false, "Couldn't check that player, try again")
			return
		end
		if saved == nil then
			reply(player, productId, false, `{name} hasn't played yet`)
			return
		end
		theirs = saved
	end
	if gift.pack and Packs.owns(theirs, gift.pack) then
		reply(player, productId, false, `{name} already has the {gift.name}`)
		return
	end

	local data = DataService.data(player)
	if data == nil or player.Parent == nil then
		return
	end
	data.giftIntent = { productId = productId, to = userId, toName = name, at = os.time() }
	reply(player, productId, true, `Gifting to {name}...`)
	MarketplaceService:PromptProductPurchase(player, productId)
	print(`[robuxgift] {player.Name} -> {name} ({userId}): prompting product {productId}`)
end

local function onRequest(player: Player, action: any, productId: any, recipient: any)
	if action == "clear" then
		local data = DataService.data(player)
		if data then
			data.giftIntent = nil
		end
		return
	end
	if action ~= "send" or type(productId) ~= "number" then
		return
	end
	local now = os.clock()
	if busy[player] or now - (lastAsk[player] or -math.huge) < RobuxGifts.REQUEST_COOLDOWN then
		reply(player, productId, false, "One moment...")
		return
	end
	lastAsk[player] = now
	busy[player] = true
	local ok, err = pcall(ask, player, productId, recipient)
	busy[player] = nil
	if not ok then
		warn(`[robuxgift] {player.Name}'s gift request errored: {err}`)
		reply(player, productId, false, "Something went wrong, try again")
	end
end

-- ── The receipt (ProductService) ──────────────────────────────────────────────

local function find(_player: Player, data: any, productId: number): any
	local intent = data.giftIntent
	if type(intent) ~= "table" or intent.productId ~= productId or type(intent.to) ~= "number" then
		return nil
	end
	if os.time() - (tonumber(intent.at) or 0) > RobuxGifts.INTENT_SECONDS then
		return nil
	end
	return intent
end

local function send(player: Player, intent: any, receipt: any): boolean
	return DataService.message(intent.to, {
		kind = MESSAGE_KIND,
		purchaseId = receipt.PurchaseId,
		productId = receipt.ProductId,
		from = player.UserId,
		fromName = player.DisplayName,
	})
end

local function sent(player: Player, data: any, intent: any)
	data.giftIntent = nil
	local item = itemName(intent.productId)
	local to = tostring(intent.toName or "them")
	-- Deferred: ProductService calls this mid-receipt, and a remote is no part of it.
	task.defer(function()
		if player.Parent then
			remote:FireClient(player, { kind = "sent", to = to, item = item })
		end
	end)
end

-- ── The delivery (each recipient's message queue) ─────────────────────────────

local function deliver(player: Player, profile: any, message: any, processed: () -> ())
	if type(message) ~= "table" or message.kind ~= MESSAGE_KIND then
		return -- not ours; leave it queued
	end
	if not profile:IsActive() or player.Parent == nil then
		return
	end
	local data = profile.Data
	local purchaseId = message.purchaseId
	local productId = message.productId
	if type(purchaseId) ~= "string" or type(productId) ~= "number" then
		warn(`[robuxgift] dropping a malformed gift for {player.Name}`)
		processed()
		return
	end
	local key = `gift:{purchaseId}`
	if ProductService.hasReceipt(data, key) then
		processed() -- a resent copy of one already opened
		return
	end
	local grant = ProductService.grantFor(productId)
	if grant == nil then
		-- Left queued: a server where the product is registered will open it.
		warn(`[robuxgift] {player.Name} has a gift of unknown product {productId}; left queued`)
		return
	end
	local ok, err = pcall(grant, player, data)
	if not ok then
		warn(`[robuxgift] gift grant for {player.Name} product {productId} errored: {err}; left queued`)
		return
	end
	ProductService.remember(data, key)
	processed()
	profile:Save()

	local from = if type(message.fromName) == "string" then message.fromName else "Someone"
	local item = itemName(productId)
	print(`[robuxgift] {player.Name} received product {productId} from {from} ({purchaseId})`)
	local wait = math.max(0, (joinedAt[player] or 0) + JOIN_SETTLE - os.clock())
	task.delay(wait, function()
		if player.Parent then
			SfxService.play(player, "robux")
			remote:FireClient(player, { kind = "received", from = from, item = item })
		end
	end)
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function RobuxGiftService.init()
	remote = Net.get("RobuxGift")
	-- In init, before ProductService.start() switches ProcessReceipt on.
	ProductService.routeGifts({ find = find, send = send, sent = sent })
end

function RobuxGiftService.start()
	remote.OnServerEvent:Connect(onRequest)

	-- A prompt closed without buying drops its intent. (For a bought one the receipt
	-- clears it.)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		if purchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local data = if player then DataService.data(player) else nil
		local intent = if data then data.giftIntent else nil
		if type(intent) == "table" and intent.productId == productId then
			data.giftIntent = nil
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = os.clock()
	end)
	for _, player in Players:GetPlayers() do
		joinedAt[player] = joinedAt[player] or os.clock()
	end
	DataService.onLoaded(function(player, _data)
		local profile = DataService.get(player)
		if profile == nil then
			return
		end
		profile:MessageHandler(function(message: any, processed: () -> ())
			deliver(player, profile, message, processed)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAsk[player] = nil
		busy[player] = nil
		joinedAt[player] = nil
	end)
end

return RobuxGiftService
