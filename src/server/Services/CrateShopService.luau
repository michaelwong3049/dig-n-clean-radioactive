--!strict
--[[
	CrateShopService.luau — the two crate pads in Base Camp, either side of the group
	chest (Config/CrateShop): cash crates on one, Robux crates on the other. Two crates
	hover side by side over each pad; each has its own E prompt that buys it.

	BUILT HERE AT RUNTIME, like the group chest: a stadium-shaped pad, and per crate a coloured plinth,
	the crate itself (Shared/CrateModels, the same model a dig hands you, scaled up) and
	a price tag. Nothing lives in the place file, so no rebuild or Publish moves it.

	THE CRATES MOVE ON THE CLIENT. Each one carries the "StationMotion" tag with Motion
	"hover" (StationMotionController): a slow turn about its own pivot plus a gentle bob.
	The server never touches their CFrames. The prompts hang off a still, invisible
	anchor under each crate, not the crate, so they don't bob.

	ONE PROMPT PER PART (two co-located prompts on one key drop presses), and the
	default OnePerButton exclusivity shows only the nearest one.

	BUYING. A cash crate: EconomyService.spend (check-and-debit in one call), then
	CrateService.give straight into the bag past capacity. A Robux crate: the server
	opens Roblox's purchase prompt; ProductService runs the grant once per receipt.
	While its product id is 0 the tag reads COMING SOON and E only says so.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Crates = require(Shared.Config.Crates)
local CrateShop = require(Shared.Config.CrateShop)
local CrateModels = require(Shared.CrateModels)
local Mastery = require(Shared.Mastery)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ProductService = require(script.Parent.ProductService)
local CrateService = require(script.Parent.CrateService)
local SfxService = require(script.Parent.SfxService)

local CrateShopService = {}

local BUY_COOLDOWN = 0.5
local TAG_DISTANCE = 50

--- Kit.MOTION_TAG. Kit is a build module, so the string is spelled out here.
local MOTION_TAG = "StationMotion"

local PAD_BLACK = Color3.fromHex("1E1F24")
local PAD_GREY = Color3.fromHex("5A5E66")
local CASH_GREEN = Color3.fromHex("5BE36B")
local ROBUX_GREEN = Color3.fromHex("3FD17A")
local SOON_GREY = Color3.fromHex("B8BCC4")

local lastBuy: { [Player]: number } = {}

-- ── Building ─────────────────────────────────────────────────────────────────

local function studded(p: BasePart)
	p.Material = Enum.Material.Plastic
	for _, face in { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
end

--- A flat disc on the floor: a Part cylinder stood upright (its axis is X).
local function disc(parent: Instance, name: string, radius: number, height: number, centre: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2)
	p.Color = color
	studded(p)
	p.Parent = parent
	return p
end

local function label(parent: Instance, name: string, text: string, y: number, h: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, h)
	l.Position = UDim2.fromScale(0, y)
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Parent = parent
	return l
end

local function priceText(offer: CrateShop.Offer): string
	if offer.cash then
		return "$" .. Mastery.short(offer.cash)
	end
	return "COMING SOON"
end

--- Fills a Robux tag's price from the product itself once the web call answers.
local function fillRobuxPrice(offer: CrateShop.Offer, price: TextLabel, prompt: ProximityPrompt, short: string)
	local productId = offer.productId or 0
	if productId == 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			price.Text = `R$ {info.PriceInRobux}`
			prompt.ObjectText = `{short}  •  R$ {info.PriceInRobux}`
		else
			price.Text = "ROBUX"
		end
	end)
end

local function buildOffer(model: Model, offer: CrateShop.Offer, base: Vector3, padTop: number)
	local def = Crates.get(offer.crateId)
	local floor = Vector3.new(base.X, padTop, base.Z + offer.offset)
	local colour = Color3.fromHex(def.color)

	local slot = Instance.new("Model")
	slot.Name = def.short or def.name

	-- A plinth in the crate's colour, and a light that reads as the crate glowing.
	local plinth = disc(slot, "Plinth", 1.9, 0.4, floor + Vector3.new(0, 0.2, 0), colour)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = 1.2
	light.Range = 9
	light.Parent = plinth

	-- The crate: the dig model, scaled up, with nothing on it that says "dug-up crate"
	-- (CrateId is what crate code keys off) -- only its CrateFx glow and bits stay.
	local crate = CrateModels.create(offer.crateId)
	for attr in crate:GetAttributes() do
		crate:SetAttribute(attr, nil)
	end
	crate.Name = "Crate"
	crate:ScaleTo(crate:GetScale() * CrateShop.CRATE_SCALE)
	local centre = floor + Vector3.new(0, CrateShop.HOVER_HEIGHT, 0)
	-- Front (-Z) to the shops (+X), the same way the chest faces.
	crate:PivotTo(CFrame.lookAt(centre, centre + Vector3.xAxis))
	crate:SetAttribute("Motion", "hover")
	crate:SetAttribute("MotionRate", 0.6)
	crate:SetAttribute("MotionAmp", 0.35)
	CollectionService:AddTag(crate, MOTION_TAG)
	crate.Parent = slot

	-- The still anchor the prompt and the price tag hang off.
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(floor + Vector3.new(0, 2.5, 0))
	anchor.Parent = slot

	local short = def.short or def.name
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = if offer.cash then `{short}  •  {priceText(offer)}` else `{short}  •  Robux`
	prompt.MaxActivationDistance = CrateShop.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	local tag = Instance.new("BillboardGui")
	tag.Name = "PriceTag"
	-- Sized in studs, not pixels, so from across the camp the tags shrink with their
	-- crates instead of piling into one another.
	tag.Size = UDim2.fromScale(4.2, 1.35)
	tag.StudsOffsetWorldSpace = Vector3.new(0, CrateShop.HOVER_HEIGHT + 1.6, 0)
	tag.MaxDistance = TAG_DISTANCE
	tag.LightInfluence = 0
	tag.Adornee = anchor
	label(tag, "Name", short, 0, 0.5, Color3.new(1, 1, 1))
	local priceColour = if offer.cash then CASH_GREEN elseif (offer.productId or 0) == 0 then SOON_GREY else ROBUX_GREEN
	local price = label(tag, "Price", priceText(offer), 0.52, 0.48, priceColour)
	tag.Parent = anchor

	if not offer.cash then
		fillRobuxPrice(offer, price, prompt, short)
	end

	prompt.Triggered:Connect(function(player: Player)
		CrateShopService.buy(player, offer)
	end)

	slot.Parent = model
end

--- A stadium on the floor: a round end under each crate, joined by a slab.
local function stadium(parent: Instance, name: string, radius: number, height: number, centre: Vector3, color: Color3)
	local spread = CrateShop.SPREAD
	disc(parent, name, radius, height, centre + Vector3.new(0, 0, spread), color)
	disc(parent, name, radius, height, centre - Vector3.new(0, 0, spread), color)
	local slab = Instance.new("Part")
	slab.Name = name
	slab.Anchored = true
	slab.Size = Vector3.new(radius * 2, height, spread * 2)
	slab.CFrame = CFrame.new(centre)
	slab.Color = color
	studded(slab)
	slab.Parent = parent
end

local function buildPad(pad: CrateShop.Pad): Model
	local model = Instance.new("Model")
	model.Name = pad.name
	-- Whole or not at all, so a streamed-in pad never arrives without its crates.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = pad.position
	local R = CrateShop.END_RADIUS
	stadium(model, "Pad", R, 0.6, base + Vector3.new(0, 0.3, 0), PAD_BLACK)
	stadium(model, "Inner", R - 1, 0.3, base + Vector3.new(0, 0.75, 0), PAD_GREY)
	local padTop = base.Y + 0.9

	for _, offer in pad.offers do
		buildOffer(model, offer, base, padTop)
	end

	-- The pad's own sign, over the middle.
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Anchored = true
	hub.Transparency = 1
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CanQuery = false
	hub.Size = Vector3.new(1, 1, 1)
	hub.CFrame = CFrame.new(base + Vector3.new(0, 1, 0))
	hub.Parent = model
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(11, 2)
	sign.StudsOffsetWorldSpace = Vector3.new(0, CrateShop.HOVER_HEIGHT + 6.5, 0)
	sign.MaxDistance = 70
	sign.LightInfluence = 0
	sign.Adornee = hub
	label(sign, "Title", pad.title, 0, 1, Color3.fromHex("F5C542"))
	sign.Parent = hub

	model.PrimaryPart = hub
	model.Parent = Workspace
	return model
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
	-- In init, not start, so no receipt can land before these are registered.
	for _, pad in CrateShop.PADS do
		for _, offer in pad.offers do
			if offer.productId then
				ProductService.register(offer.productId, function(player, data)
					grantRobux(player, data, offer.crateId)
				end)
			end
		end
	end
end

function CrateShopService.start()
	for _, pad in CrateShop.PADS do
		buildPad(pad)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
end

return CrateShopService
