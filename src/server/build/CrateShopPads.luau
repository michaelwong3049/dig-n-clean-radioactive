--!strict
--[[
	CrateShopPads.luau — the crate pads: Base Camp's two either side of the group chest,
	and a cash + Robux pair on every camp's plaza (Config/CrateShop,
	Services/CrateShopService). World.rebuild() bakes them into the
	place, so they show in Studio's Edit mode like the rest of the map.

	Each pad is a stadium-shaped pad and, per crate, a coloured plinth, the crate itself
	(Shared/CrateModels, the same model a dig hands you, scaled up), a still invisible
	Anchor carrying the BuyPrompt, and a PriceTag. A top-level Model per pad, named
	pad.name, straight under Workspace.

	THIS BUILDS LOOKS ONLY. CrateShopService finds each pad at runtime and wires the
	prompts and the Robux price. If a pad is missing (a place saved before this module
	existed), the service calls CrateShopPads.build itself, so the crates never vanish.

	THE CRATES MOVE ON THE CLIENT. Each one carries the "StationMotion" tag with Motion
	"hover" (StationMotionController): a slow turn about its own pivot plus a gentle bob.
	The prompts hang off the Anchor, not the crate, so they don't bob.

	NAMES THE SERVICE READS (keep these):
	    <slot>.ShopCrateId      attribute on each crate's slot Model, its Config/Crates id
	    <slot>.Anchor.BuyPrompt the ProximityPrompt
	    <slot>.Anchor.PriceTag.Price  the price line, rewritten with the Robux price
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Camps = require(Shared.Config.Camps)
local Stages = require(Shared.Config.Stages)
local Crates = require(Shared.Config.Crates)
local CrateShop = require(Shared.Config.CrateShop)
local CrateModels = require(Shared.CrateModels)
local Mastery = require(Shared.Mastery)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local CrateShopPads = {}

CrateShopPads.CRATE_ATTR = "ShopCrateId"
CrateShopPads.PROMPT_NAME = "BuyPrompt"

local TAG_DISTANCE = 50

local PAD_BLACK = Color3.fromHex("1E1F24")
local PAD_GREY = Color3.fromHex("5A5E66")
local CASH_GREEN = Color3.fromHex("5BE36B")
local ROBUX_GREEN = Color3.fromHex("3FD17A")
local SOON_GREY = Color3.fromHex("B8BCC4")

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

--- The price as it reads before the service has asked Roblox for a Robux price.
function CrateShopPads.priceText(offer: CrateShop.Offer): string
	if offer.cash then
		return "$" .. Mastery.short(offer.cash)
	end
	return if (offer.productId or 0) == 0 then "COMING SOON" else "ROBUX"
end

--- Where a pad stands, on the floor. A camp pad sits off that camp's plaza centre --
--- the grid cell nearest its disc centre, the same one build/CampSite lays out from --
--- on the plaza's top (CampSite's PLAZA_Y).
function CrateShopPads.positionOf(pad: CrateShop.Pad): Vector3
	if pad.position then
		return pad.position
	end
	local campKey = pad.camp :: string
	for _, def in Camps.DEFS do
		if def.key == campKey then
			local center = def.center :: { number }
			local ox, oz = Hub.cellCentre(center[1], center[2])
			return Vector3.new(ox, Stages.SURFACE_Y + Hub.PLAZA_LIFT, oz) + (pad.offset or Vector3.zero)
		end
	end
	error(`CrateShopPads: {pad.name} names no camp "{campKey}"`)
end

local function buildOffer(model: Model, offer: CrateShop.Offer, base: Vector3, padTop: number, facing: Vector3)
	local def = Crates.get(offer.crateId)
	local floor = Vector3.new(base.X, padTop, base.Z + offer.offset)
	local colour = Color3.fromHex(def.color)

	local slot = Instance.new("Model")
	slot.Name = def.short or def.name
	slot:SetAttribute(CrateShopPads.CRATE_ATTR, offer.crateId)

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
	-- Front (-Z) the way the pad faces: to the shops (+X) at Base Camp, the same way the
	-- chest faces; at a camp, to the entry path you walk in by.
	crate:PivotTo(CFrame.lookAt(centre, centre + facing))
	crate:SetAttribute("Motion", "hover")
	crate:SetAttribute("MotionRate", 0.6)
	crate:SetAttribute("MotionAmp", 0.35)
	CollectionService:AddTag(crate, Kit.MOTION_TAG)
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
	prompt.Name = CrateShopPads.PROMPT_NAME
	prompt.ActionText = "Buy"
	prompt.ObjectText = if offer.cash then `{short}  •  {CrateShopPads.priceText(offer)}` else `{short}  •  Robux`
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
	label(tag, "Price", CrateShopPads.priceText(offer), 0.52, 0.48, priceColour)
	tag.Parent = anchor

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

--- One pad, fully formed and UNPARENTED (Kit.swap's contract).
function CrateShopPads.build(pad: CrateShop.Pad): Model
	local model = Instance.new("Model")
	model.Name = pad.name
	-- Whole or not at all, so a streamed-in pad never arrives without its crates.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = CrateShopPads.positionOf(pad)
	local R = CrateShop.END_RADIUS
	stadium(model, "Pad", R, 0.6, base + Vector3.new(0, 0.3, 0), PAD_BLACK)
	stadium(model, "Inner", R - 1, 0.3, base + Vector3.new(0, 0.75, 0), PAD_GREY)
	local padTop = base.Y + 0.9

	for _, offer in pad.offers do
		buildOffer(model, offer, base, padTop, pad.facing)
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
	return model
end

--- Bake every pad into Workspace (World.rebuild).
function CrateShopPads.rebuild(parent: Instance?)
	for _, pad in CrateShop.PADS do
		Kit.swap(pad.name, function()
			return CrateShopPads.build(pad)
		end, parent)
	end
	print(`[build] Crate pads rebuilt — {#CrateShop.PADS} pad(s)`)
end

return CrateShopPads
