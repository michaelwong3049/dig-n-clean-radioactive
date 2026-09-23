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
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local ProductService = {}

-- How many PurchaseIds a profile remembers. Retries arrive within a session or two,
-- so a short tail is enough and the save never grows.
local RECEIPT_MEMORY = 50

local grants: { [number]: (player: Player, data: any) -> () } = {}

--- Sell a product: `grant(player, data)` runs once per real purchase. Id 0 means "not
--- set up on the dashboard yet" and registers nothing.
function ProductService.register(productId: number, grant: (player: Player, data: any) -> ())
	if productId == 0 then
		return
	end
	assert(grants[productId] == nil, `ProductService: product {productId} registered twice`)
	grants[productId] = grant
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

	if table.find(data.receipts, purchaseId) == nil then
		local ok, err = pcall(grant, player, data)
		if not ok then
			warn(`[product] grant for {player.Name} product {receipt.ProductId} errored: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #data.receipts >= RECEIPT_MEMORY do
			table.remove(data.receipts, 1)
		end
		table.insert(data.receipts, purchaseId)
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

function ProductService.start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ProductService
