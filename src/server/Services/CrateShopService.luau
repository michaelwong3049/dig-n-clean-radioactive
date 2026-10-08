--!strict
--[[
	CrateShopService.luau — the crate pads (Config/CrateShop): Base Camp's two either side
	of the group chest, and a pair on every camp's plaza. Cash crates on one of each pair,
	Robux crates on the other. Two crates
	hover side by side over each pad; each has its own E prompt that buys it.

	THE PADS ARE BAKED INTO THE PLACE by build/CrateShopPads (World.rebuild), so they
	show in Studio's Edit mode. This service only finds them and wires the prompts, the
	prices and the Robux price lookup. A place saved before that existed has no pads,
	so a missing pad is built here at runtime instead: the crates never just vanish.
	Moving a pad means a world rebuild + Save + Publish.

	The crates hover on the client (StationMotionController); the server never touches
	their CFrames. The prompts hang off a still Anchor, so they don't bob.

	ONE PROMPT PER PART (two co-located prompts on one key drop presses), and the
	default OnePerButton exclusivity shows only the nearest one.

	BUYING. E on a crate opens a confirm popup on the client (CratePurchase
	{ kind = "offer" }); its BUY comes back as CratePurchase("buy", pad, crateId), range-
	checked against the crate's anchor. Then: EconomyService.spend (check-and-debit in one call), then
	CrateService.give straight into the bag past capacity. A Robux crate: the server
	opens Roblox's purchase prompt; ProductService runs the grant once per receipt.
	While its product id is 0 the tag reads COMING SOON and E only says so.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Crates = require(Shared.Config.Crates)
local CrateShop = require(Shared.Config.CrateShop)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ProductService = require(script.Parent.ProductService)
local CrateService = require(script.Parent.CrateService)
local SfxService = require(script.Parent.SfxService)
local CrateShopPads = require(script.Parent.Parent.build.CrateShopPads)

local CrateShopService = {}

local BUY_COOLDOWN = 0.5
--- A popup BUY from further than this from the crate's anchor is refused. The client
--- closes the popup at 14, so a real player never hits it.
local BUY_REACH = 18

local lastBuy: { [Player]: number } = {}
local purchaseRemote: RemoteEvent = nil
--- Each cash offer's anchor, by `{pad name}/{crateId}`, for the popup's range check.
local anchors: { [string]: BasePart } = {}
--- Each Robux product's price once GetProductInfo has answered, for the popup.
local robuxPrice: { [number]: number } = {}

-- ── Wiring ───────────────────────────────────────────────────────────────────

--- Fills a Robux tag's price from the product itself once the web call answers.
local function fillRobuxPrice(offer: CrateShop.Offer, price: TextLabel?, prompt: ProximityPrompt, short: string)
	local productId = offer.productId or 0
	if productId == 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		local robux = if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then info.PriceInRobux else nil
		if price then
			price.Text = if robux then `R$ {robux}` else "ROBUX"
		end
		if robux then
			prompt.ObjectText = `{short}  •  R$ {robux}`
			robuxPrice[productId] = robux
		end
	end)
end

--- The pad as the place has it, or built now when the saved place predates the baked
--- pads (or someone deleted one): the crates must never just be missing.
local function findOrBuildPad(pad: CrateShop.Pad): Model
	local existing = Workspace:FindFirstChild(pad.name)
	if existing and existing:IsA("Model") then
		return existing
	end
	warn(`[crateshop] Workspace.{pad.name} is missing; building it at runtime (rebuild the world + Save to bake it)`)
	local model = CrateShopPads.build(pad)
	model.Parent = Workspace
	return model
end

local function findSlot(model: Model, crateId: string): Instance?
	for _, child in model:GetChildren() do
		if child:GetAttribute(CrateShopPads.CRATE_ATTR) == crateId then
			return child
		end
	end
	return nil
end

local function wirePad(pad: CrateShop.Pad)
	local model = findOrBuildPad(pad)
	for _, offer in pad.offers do
		local slot = findSlot(model, offer.crateId)
		local anchor = slot and slot:FindFirstChild("Anchor")
		local prompt = anchor and anchor:FindFirstChild(CrateShopPads.PROMPT_NAME)
		if prompt == nil or not prompt:IsA("ProximityPrompt") then
			warn(`[crateshop] {pad.name} has no {CrateShopPads.PROMPT_NAME} for {offer.crateId}; rebuild the world`)
			continue
		end
		-- Re-stamped from the config, so a price change needs no rebuild to be honest.
		local def = Crates.get(offer.crateId)
		local short = def.short or def.name
		prompt.ObjectText = if offer.cash then `{short}  •  {CrateShopPads.priceText(offer)}` else `{short}  •  Robux`
		local tag = anchor and anchor:FindFirstChild("PriceTag")
		local price = tag and tag:FindFirstChild("Price")
		local priceLabel = if price and price:IsA("TextLabel") then price else nil
		if priceLabel then
			priceLabel.Text = CrateShopPads.priceText(offer)
		end
		if not offer.cash then
			fillRobuxPrice(offer, priceLabel, prompt, short)
		end
		if anchor and anchor:IsA("BasePart") then
			anchors[`{pad.name}/{offer.crateId}`] = anchor
		end
		prompt.Triggered:Connect(function(player: Player)
			-- Ask first, on request, cash and Robux crates alike (a Robux BUY then opens
			-- Roblox's own purchase window). A product not made yet just says so.
			if anchor and anchor:IsA("BasePart") and (offer.cash or (offer.productId or 0) ~= 0) then
				local data = DataService.data(player)
				purchaseRemote:FireClient(player, {
					kind = "offer",
					pad = pad.name,
					crateId = offer.crateId,
					price = offer.cash or robuxPrice[offer.productId or 0] or 0,
					robux = offer.cash == nil,
					cash = if data then data.cash else nil,
					anchor = anchor,
				})
				return
			end
			CrateShopService.buy(player, offer)
		end)
	end
end

-- ── Buying ───────────────────────────────────────────────────────────────────

--- A Robux crate's grant: one crate per receipt. Mutates `data` and never yields
--- (ProductService's contract); the notice waits until the receipt step is done.
local function grantRobux(player: Player, data: any, crateId: string)
	CrateService.give(data, crateId)
	local name = Crates.get(crateId).name
	task.defer(function()
		CrateService.notify(player, `{name} added to your bag`)
	end)
end

--- Buy one crate. Returns (ok, why) for the popup; a Robux crate only opens Roblox's
--- purchase prompt, so its ok means "asked", not "bought".
function CrateShopService.buy(player: Player, offer: CrateShop.Offer): (boolean, string?)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < BUY_COOLDOWN then
		return false, "slow down a moment"
	end
	lastBuy[player] = now

	local def = Crates.get(offer.crateId)
	if offer.cash then
		local data = DataService.data(player)
		if data == nil then
			return false, "your save hasn't loaded"
		end
		local ok, why = EconomyService.spend(player, offer.cash)
		if not ok then
			return false, why
		end
		CrateService.give(data, offer.crateId)
		SfxService.play(player, "purchase")
		CrateService.notify(player, `{def.name} added to your bag`)
		print(`[crateshop] {player.Name} bought {offer.crateId} for ${offer.cash}`)
		return true, nil
	end

	local productId = offer.productId or 0
	if productId == 0 then
		CrateService.notify(player, `The {def.name} is coming soon`)
		return false, "coming soon"
	end
	MarketplaceService:PromptProductPurchase(player, productId)
	return true, nil
end

--- The popup's BUY: the offer must be a real crate on that pad, and the player
--- must still be standing at it.
local function onPurchase(player: Player, verb: any, padName: any, crateId: any)
	if verb ~= "buy" or type(padName) ~= "string" or type(crateId) ~= "string" then
		return
	end
	local offer: CrateShop.Offer? = nil
	for _, pad in CrateShop.PADS do
		if pad.name == padName then
			for _, candidate in pad.offers do
				if candidate.crateId == crateId then
					offer = candidate
				end
			end
		end
	end
	local anchor = anchors[`{padName}/{crateId}`]
	if offer == nil or anchor == nil then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local ok, why
	if root == nil or not root:IsA("BasePart") or (root.Position - anchor.Position).Magnitude > BUY_REACH then
		ok, why = false, "walk back to the crate"
	else
		ok, why = CrateShopService.buy(player, offer)
	end
	local data = DataService.data(player)
	purchaseRemote:FireClient(player, {
		kind = "result",
		ok = ok,
		message = why,
		crateId = crateId,
		cash = if data then data.cash else nil,
	})
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function CrateShopService.init()
	purchaseRemote = Net.get("CratePurchase")
	-- In init, not start, so no receipt can land before these are registered. Every
	-- camp's Robux pad sells the same products, so each one registers once.
	local registered: { [number]: boolean } = {}
	for _, pad in CrateShop.PADS do
		for _, offer in pad.offers do
			local productId = offer.productId
			if productId and not registered[productId] then
				registered[productId] = true
				ProductService.register(productId, function(player, data)
					grantRobux(player, data, offer.crateId)
				end)
			end
		end
	end
end

function CrateShopService.start()
	purchaseRemote.OnServerEvent:Connect(onPurchase)
	for _, pad in CrateShop.PADS do
		wirePad(pad)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
end

return CrateShopService
