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

	THE IMPORTED PADS (user's import, 2026-10-08): when the place has
	ServerStorage.StationTemplates.CratePadCash (grey) and .CratePadPremium (gold), each
	crate hovers over its own copy -- grey under the cash crates, gold under the Robux
	ones -- in place of the stadium and plinth. Without the template a pad keeps its parts.

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
local ImportedStation = require(script.Parent.ImportedStation)

local CrateShopPads = {}

CrateShopPads.CRATE_ATTR = "ShopCrateId"
CrateShopPads.PROMPT_NAME = "BuyPrompt"

local TAG_DISTANCE = 50

-- The imported pads (ServerStorage.StationTemplates), scaled so each is this wide: just
-- under the 2 x SPREAD between two crates, so a pair sits side by side with a seam.
local CASH_PAD_TEMPLATE = "CratePadCash"
local PREMIUM_PAD_TEMPLATE = "CratePadPremium"
local IMPORTED_PAD_WIDTH = 6.3

local PAD_BLACK = Color3.fromHex("1E1F24")
local PAD_GREY = Color3.fromHex("5A5E66")
local PRICE_GREEN = Color3.fromHex("7CF25A") -- UIKit.House.cash
local SOON_GREY = Color3.fromHex("B8BCC4")

-- The pad sign's title, top to bottom (user's pick, 2026-10-08): white into green over
-- the cash pad, cream into orange over the Robux one.
local CASH_TITLE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFFFFF")),
	ColorSequenceKeypoint.new(0.45, Color3.fromHex("B8FF8F")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("3FD17A")),
})
local PREMIUM_TITLE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFF6C8")),
	ColorSequenceKeypoint.new(0.45, Color3.fromHex("FFD34D")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("FF9A1F")),
})

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

--- A heavier outline than TextStroke: a UIStroke, which a UIGradient on the label leaves
--- black (a gradient tints the legacy TextStroke along with the text).
local function outline(l: TextLabel, thickness: number)
	l.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = l
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

--- The imported pad under one crate, its foot on `ground`. Returns the look and its top.
local function importedPad(slot: Model, template: Model, ground: Vector3): (Model, number)
	local _, native = template:GetBoundingBox()
	local scale = IMPORTED_PAD_WIDTH / math.max(native.X, native.Z)
	local look = ImportedStation.place(template, slot, CFrame.new(ground), scale)
	look.Name = "PadLook"
	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") then
			-- Walkable however thin its trim came out.
			d.CanCollide = true
			d.CanQuery = true
		end
	end
	local box, size = look:GetBoundingBox()
	return look, box.Position.Y + size.Y / 2
end

local function buildOffer(
	model: Model,
	offer: CrateShop.Offer,
	base: Vector3,
	padTop: number,
	facing: Vector3,
	padTemplate: Model?
)
	local def = Crates.get(offer.crateId)
	local colour = Color3.fromHex(def.color)

	local slot = Instance.new("Model")
	slot.Name = def.short or def.name
	slot:SetAttribute(CrateShopPads.CRATE_ATTR, offer.crateId)

	-- The crate's own pad (imported) or a plinth in its colour, and a light that reads
	-- as the crate glowing.
	local glowFrom: BasePart
	local floor: Vector3
	if padTemplate then
		local look, top = importedPad(slot, padTemplate, Vector3.new(base.X, base.Y, base.Z + offer.offset))
		floor = Vector3.new(base.X, top, base.Z + offer.offset)
		glowFrom = look:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	else
		floor = Vector3.new(base.X, padTop, base.Z + offer.offset)
		glowFrom = disc(slot, "Plinth", 1.9, 0.4, floor + Vector3.new(0, 0.2, 0), colour)
	end
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = 1.2
	light.Range = 9
	light.Parent = glowFrom

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
	-- 6 wide leaves a gap between the two tags (crates sit 2 x SPREAD = 6.6 apart).
	tag.Size = UDim2.fromScale(6, 2.2)
	tag.StudsOffsetWorldSpace = Vector3.new(0, CrateShop.HOVER_HEIGHT + 2, 0)
	tag.MaxDistance = TAG_DISTANCE
	tag.LightInfluence = 0
	tag.Adornee = anchor
	-- The name in the crate's own colour, the price under it a size up.
	outline(label(tag, "Name", short, 0, 0.45, colour), 2)
	local priceColour = if offer.cash or (offer.productId or 0) ~= 0 then PRICE_GREEN else SOON_GREY
	outline(label(tag, "Price", CrateShopPads.priceText(offer), 0.45, 0.55, priceColour), 2.5)
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
	local robuxPad = pad.offers[1] ~= nil and pad.offers[1].cash == nil
	local padTemplate = ImportedStation.template(if robuxPad then PREMIUM_PAD_TEMPLATE else CASH_PAD_TEMPLATE)
	local padTop = base.Y + 0.9
	if padTemplate == nil then
		local R = CrateShop.END_RADIUS
		stadium(model, "Pad", R, 0.6, base + Vector3.new(0, 0.3, 0), PAD_BLACK)
		stadium(model, "Inner", R - 1, 0.3, base + Vector3.new(0, 0.75, 0), PAD_GREY)
	end

	for _, offer in pad.offers do
		buildOffer(model, offer, base, padTop, pad.facing, padTemplate)
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
	sign.Size = UDim2.fromScale(14, 3.2)
	sign.StudsOffsetWorldSpace = Vector3.new(0, CrateShop.HOVER_HEIGHT + 7.6, 0)
	sign.MaxDistance = 70
	sign.LightInfluence = 0
	sign.Adornee = hub
	-- A black copy a notch lower is the drop shadow; the title proper is white under a
	-- top-to-bottom gradient.
	local shadow = label(sign, "TitleShadow", pad.title, 0.06, 0.94, Color3.new(0, 0, 0))
	outline(shadow, 3)
	local title = label(sign, "Title", pad.title, 0, 0.94, Color3.new(1, 1, 1))
	outline(title, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = if robuxPad then PREMIUM_TITLE else CASH_TITLE
	gradient.Rotation = 90
	gradient.Parent = title
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
