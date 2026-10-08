--!strict
--[[
	ProductService.luau — Robux developer products (PLAN §11). The ONE owner of
	MarketplaceService.ProcessReceipt.

	ProcessReceipt is a single callback per game: the second service to assign it
	silently replaces the first, and every product the first one sold stops being
	granted. So nothing else in the game touches it. A service that sells something
	registers a grant function here by product id (LuckBoostService registers the Lucky
	Clover) and this file does the part that is easy to get wrong.

	THE PART THAT IS EASY TO GET WRONG is granting exactly once. Roblox re-sends a
	receipt until it hears PurchaseGranted -- after a crash, a timeout, a server
	shutdown, on the buyer's next join -- so "grant, then return Granted" double-grants
	the moment anything between those two steps fails. The fix is ProfileStore's own
	recipe: the PurchaseId goes into the SAVE (`data.receipts`) in the same step as the
	grant, and Granted is only returned once a save containing it has landed
	(`OnAfterSave`). A retry that finds its id already there grants nothing and just
	waits for that save.

	A GRANT FUNCTION MUST ONLY MUTATE `data` AND MUST NOT YIELD. It runs inside the
	same step that records the id, so the two can never be saved apart.

	GIFTS (Services/RobuxGiftService). If the buyer pressed a gift button for this
	product, the receipt is not granted to them. It is sent to the recipient's save as
	a message (that step yields), and only then is the PurchaseId recorded on the
	BUYER's save. A crash between the two resends the message on retry. The recipient
	keeps "gift:<PurchaseId>" in their OWN `receipts` when they open it, so a second copy
	grants nothing.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local SfxService = require(script.Parent.SfxService)

local ProductService = {}

-- How many PurchaseIds a profile remembers. Retries arrive within a session or two,
-- so a short tail is enough and the save never grows.
local RECEIPT_MEMORY = 50

local grants: { [number]: (player: Player, data: any) -> () } = {}

export type GiftRoute = {
	-- The buyer's pending gift for this product, or nil to grant it to them as usual.
	find: (player: Player, data: any, productId: number) -> any,
	-- Deliver it. YIELDS; true once the recipient's save holds it.
	send: (player: Player, intent: any, receipt: any) -> boolean,
	-- After the PurchaseId is recorded on the buyer: clear the intent and tell them.
	sent: (player: Player, data: any, intent: any) -> (),
}
local gifts: GiftRoute? = nil

--- Sell a product: `grant(player, data)` runs once per real purchase. Id 0 means "not
--- set up on the dashboard yet" and registers nothing.
function ProductService.register(productId: number, grant: (player: Player, data: any) -> ())
	if productId == 0 then
		return
	end
	assert(grants[productId] == nil, `ProductService: product {productId} registered twice`)
	grants[productId] = grant
end

--- The grant registered for this product, or nil. RobuxGiftService runs it for a
--- gift's recipient, under the same rules (mutate `data`, never yield).
function ProductService.grantFor(productId: number): ((player: Player, data: any) -> ())?
	return grants[productId]
end

--- Has this save already been granted PurchaseId?
function ProductService.hasReceipt(data: any, purchaseId: string): boolean
	return data.receipts ~= nil and table.find(data.receipts, purchaseId) ~= nil
end

--- Record PurchaseId on this save, keeping the last RECEIPT_MEMORY.
function ProductService.remember(data: any, purchaseId: string)
	if data.receipts == nil then
		data.receipts = {}
	end
	while #data.receipts >= RECEIPT_MEMORY do
		table.remove(data.receipts, 1)
	end
	table.insert(data.receipts, purchaseId)
end

--- Send gifted receipts somewhere else (RobuxGiftService). Set once.
function ProductService.routeGifts(route: GiftRoute)
	assert(gifts == nil, "ProductService: gift route set twice")
	gifts = route
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local grant = grants[receipt.ProductId]
	if grant == nil then
		warn(`[product] receipt for unknown product {receipt.ProductId} -- not granted`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Not in this server (or not loaded yet): Roblox retries on their next join.
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if player then DataService.get(player) else nil
	if player == nil or profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId: string = receipt.PurchaseId
	local data = profile.Data
	if data.receipts == nil then
		data.receipts = {}
	end

	local intent = if gifts and table.find(data.receipts, purchaseId) == nil then gifts.find(player, data, receipt.ProductId) else nil
	if intent and gifts then
		local ok, delivered = pcall(gifts.send, player, intent, receipt)
		if not ok then
			warn(`[product] gift from {player.Name} product {receipt.ProductId} errored: {delivered}`)
		end
		-- Sending yields: they may have left, or a retry of this receipt may have
		-- finished first.
		if not (ok and delivered) or not profile:IsActive() then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if table.find(data.receipts, purchaseId) == nil then
			ProductService.remember(data, purchaseId)
			gifts.sent(player, data, intent)
			SfxService.play(player, "robux")
			print(`[product] {player.Name} gifted product {receipt.ProductId} ({purchaseId})`)
		end
	elseif table.find(data.receipts, purchaseId) == nil then
		local ok, err = pcall(grant, player, data)
		if not ok then
			warn(`[product] grant for {player.Name} product {receipt.ProductId} errored: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		ProductService.remember(data, purchaseId)
		SfxService.play(player, "robux")
		print(`[product] {player.Name} bought product {receipt.ProductId} ({purchaseId})`)
	end

	-- Granted only once a save that carries the id has landed.
	local decision: Enum.ProductPurchaseDecision? = nil
	local function check(saved: any)
		if saved and saved.receipts and table.find(saved.receipts, purchaseId) then
			decision = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	check(profile.LastSavedData)
	local connection = profile.OnAfterSave:Connect(check)
	if decision == nil then
		profile:Save()
	end
	while decision == nil and profile:IsActive() do
		task.wait()
	end
	connection:Disconnect()

	return decision or Enum.ProductPurchaseDecision.NotProcessedYet
end

--- Run a made-up receipt through the real path (DebugService's /robuxgift). YIELDS.
function ProductService.debugReceipt(receipt: any): Enum.ProductPurchaseDecision
	return processReceipt(receipt)
end

function ProductService.start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ProductService
