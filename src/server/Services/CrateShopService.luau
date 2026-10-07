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

	BUYING. A cash crate: EconomyService.spend (check-and-debit in one call), then
	CrateService.give straight into the bag past capacity. A Robux crate: the server
	opens Roblox's purchase prompt; ProductService runs the grant once per receipt.
	While its product id is 0 the tag reads COMING SOON and E only says so.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
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

local lastBuy: { [Player]: number } = {}

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
		prompt.Triggered:Connect(function(player: Player)
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

function CrateShopService.buy(player: Player, offer: CrateShop.Offer)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < BUY_COOLDOWN then
		return
	end
	lastBuy[player] = now

	local def = Crates.get(offer.crateId)
	if offer.cash then
		local data = DataService.data(player)
		if data == nil then
			return
		end
		local ok, why = EconomyService.spend(player, offer.cash)
		if not ok then
			CrateService.notify(player, `Can't buy the {def.name}: {why}`)
			return
		end
		CrateService.give(data, offer.crateId)
		SfxService.play(player, "purchase")
		CrateService.notify(player, `{def.name} added to your bag`)
		print(`[crateshop] {player.Name} bought {offer.crateId} for ${offer.cash}`)
		return
	end

	local productId = offer.productId or 0
	if productId == 0 then
		CrateService.notify(player, `The {def.name} is coming soon`)
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function CrateShopService.init()
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
	for _, pad in CrateShop.PADS do
		wirePad(pad)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
end

return CrateShopService
