--!strict
--[[
	SlagFurnace.luau — the Slag Furnace (Services/FurnaceService, Config/Furnace).
	Built by build/CampSite on the south deck in every site camp whose Config/Camps entry
	sets `furnace` (Magma Hollow).

	A BLAST FURNACE: three stepped basalt courses with an ember crown, a hopper on top
	that a ramp climbs to (where the nukes go in), a glowing mouth at the front, a spout
	pouring into a slag channel that runs to a mould, a heat gauge, two chimneys and a
	pile of cooled slag beside it. When the place has ServerStorage.StationTemplates.
	SlagFurnace, that imported model is the look instead (build/ImportedStation).

	AUTHORED FACING +Z (the player walks up from +Z), origin at the deck's top face,
	centred on the machine. Nothing here moves on the server. The flare (the mouth and
	the hopper turning Neon, sparks out of the hopper) is
	client/Controllers/FurnaceStationController's, driven off the attributes
	FurnaceService writes on this model.

	NAMED PARTS THE CLIENT READS (keep these names):
	    Embers          the glow inside the furnace mouth
	    HopperMouth     the molten surface inside the hopper
	    SparkPoint      invisible, over the hopper, where the sparks fly from
	    FurnaceStation  StationKind = "furnace", StationId = the camp key, "OpenFurnace" prompt

	MATTE, LIKE EVERY OTHER PROP (Kit's palette note). The molten parts read orange by
	colour, not Neon, and there is no standing light; the client lights them mid-flare.
]]

local CollectionService = game:GetService("CollectionService")

local ImportedStation = require(script.Parent.ImportedStation)
local Kit = require(script.Parent.Kit)

local SlagFurnace = {}

SlagFurnace.MODEL_NAME = "SlagFurnace"
SlagFurnace.STATION_NAME = "FurnaceStation"
SlagFurnace.PROMPT_NAME = "OpenFurnace"
SlagFurnace.TAG = "SlagFurnace"

--- How far in front of the machine the panel answers, and its footprint.
SlagFurnace.RADIUS = 10
SlagFurnace.HALF_X = 13
SlagFurnace.HALF_Z = 8
--- The imported look is ~0.88 x 1.09 x 0.64 studs as it comes in.
SlagFurnace.IMPORT_SCALE = 30

--- The import is near-black with dull red molten bits; it is repainted to glow red-hot
--- (ImportedStation.paint): heated red-brown iron with glowing masonry seams, deep red
--- cracks and vents, the mouth hotter toward its yellow heart, the chimney fire and the
--- pour orange. Fangs, studs, chains and bones keep the import's colours.
local IMPORT_PAINT: { [string]: ImportedStation.Paint } = {
	body = { color = "5A2A1E" },
	upper_hood = { color = "52261C" },
	hood_band = { color = "D8340E", neon = true },
	masonry_line = { color = "C8280A", neon = true },
	corner_pillar = { color = "40221B" },
	pillar_cap = { color = "4E2C22" },
	chimney = { color = "4A261D" },
	chimney_band = { color = "C8280A", neon = true },
	plinth = { color = "3E3430" },
	mouth_lava = { color = "FF2A0A", neon = true },
	mouth_core = { color = "FF6A14", neon = true },
	mouth_heart = { color = "FFB43C", neon = true },
	lava_crack = { color = "FF3A0E", neon = true },
	lava_crack_branch = { color = "FF3A0E", neon = true },
	vent_slit = { color = "FF4A12", neon = true },
	chimney_fire = { color = "FF7A1E", neon = true },
	sill_lava_drip = { color = "FF5A14", neon = true },
	lava_pour = { color = "FF6A18", neon = true },
	basin_lava = { color = "FF5A14", neon = true },
}

local build = Kit.build
local R = Kit.R

local COLOR = {
	plinth = "342D2A",
	basalt = "3B3330",
	basaltDark = "2C2624",
	iron = "2E3238",
	steel = "59636D",
	mouth = "1A1412",
	ember = "FF6A1A",
	molten = "FF7A2E",
	crust = "B84A1A",
	slag = "4E423C",
	slagDark = "3A302C",
	hazYellow = "FFC21A",
	hazBlack = "22252A",
	plate = "22272C",
	dial = "E8E2D6",
	needle = "E5281F",
}

local PLINTH_H = 1.2
--- The three stepped courses, bottom to top: width, height, depth.
local COURSES = {
	{ w = 13, h = 6, d = 8 },
	{ w = 11, h = 4.5, d = 7 },
	{ w = 9, h = 3, d = 6 },
}
local BODY_Z = -2.5

local function part(
	parent: Instance,
	origin: CFrame,
	name: string,
	pos: { number },
	size: { number },
	color: string,
	extra: { [string]: any }?
): BasePart
	local spec: any = {
		name = name,
		pos = pos,
		size = size,
		color = color,
		material = "SmoothPlastic",
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return build(parent, origin, spec)
end

--- The stepped body, the ember crown and the hopper. Returns the bottom course and the
--- hopper's top height.
local function buildBody(m: Model, origin: CFrame): (BasePart, number)
	local y = PLINTH_H
	local bottom: BasePart? = nil
	for index, c in COURSES do
		local course = part(m, origin, `Course{index}`, { 0, y + c.h / 2, BODY_Z }, { c.w, c.h, c.d }, if index % 2 == 1
			then COLOR.basalt
			else COLOR.basaltDark, { studs = true })
		bottom = bottom or course
		-- A glowing seam where each course sits on the one below.
		part(m, origin, `Seam{index}`, { 0, y + c.h - 0.2, BODY_Z }, { c.w + 0.3, 0.4, c.d + 0.3 }, COLOR.crust, {
			canCollide = false,
		})
		y += c.h
	end

	-- The hopper: an iron rim round a molten well, nukes go in here.
	local top = COURSES[#COURSES]
	part(m, origin, "HopperRim", { 0, y + 0.6, BODY_Z }, { top.w + 1, 1.2, top.d + 1 }, COLOR.iron)
	part(m, origin, "HopperMouth", { 0, y + 1.05, BODY_Z }, { top.w - 1.4, 0.2, top.d - 1.4 }, COLOR.molten, {
		canCollide = false,
	})
	local spark = part(m, origin, "SparkPoint", { 0, y + 1.6, BODY_Z }, { 0.2, 0.2, 0.2 }, COLOR.steel, {
		transparency = 1,
		canCollide = false,
	})
	spark.CanQuery = false
	spark.CanTouch = false
	return bottom :: BasePart, y + 1.2
end

local function buildMouth(m: Model, origin: CFrame)
	local front = BODY_Z + COURSES[1].d / 2
	part(m, origin, "Mouth", { 0, PLINTH_H + 2.4, front + 0.05 }, { 5.5, 3.4, 0.1 }, COLOR.mouth, { canCollide = false })
	part(m, origin, "MouthArch", { 0, PLINTH_H + 4.35, front + 0.2 }, { 6.6, 0.6, 0.4 }, COLOR.iron, { canCollide = false })
	for _, x in { -3, 3 } do
		part(m, origin, "MouthPost", { x, PLINTH_H + 2.4, front + 0.2 }, { 0.6, 3.4, 0.4 }, COLOR.iron, { canCollide = false })
	end
	part(m, origin, "Embers", { 0, PLINTH_H + 1.3, front + 0.15 }, { 4.6, 1.1, 0.2 }, COLOR.ember, { canCollide = false })

	-- The nameplate across the second course.
	local plate = part(m, origin, "NamePlate", { 0, PLINTH_H + COURSES[1].h + 2.2, BODY_Z + COURSES[2].d / 2 + 0.06 }, { 8.4, 1.4, 0.12 }, COLOR.plate, {
		canCollide = false,
	})
	-- Back is +Z, the face the player walks up to (a part's Front is its -Z).
	Kit.surfaceText(plate, Enum.NormalId.Back, "SLAG FURNACE", COLOR.molten)

	-- The heat gauge, front-left of the mouth: a dial with a needle in the red.
	local gx, gy, gz = -4.7, PLINTH_H + 4.3, front + 0.2
	part(m, origin, "GaugeRim", { gx, gy, gz }, { 0.3, 2.2, 2.2 }, COLOR.iron, {
		shape = "Cylinder",
		rot = R.cylAlongZ,
		canCollide = false,
	})
	part(m, origin, "GaugeFace", { gx, gy, gz + 0.12 }, { 0.1, 1.8, 1.8 }, COLOR.dial, {
		shape = "Cylinder",
		rot = R.cylAlongZ,
		canCollide = false,
	})
	part(m, origin, "GaugeNeedle", { gx + 0.3, gy + 0.25, gz + 0.2 }, { 0.12, 0.8, 0.05 }, COLOR.needle, {
		rot = Kit.ang(0, 0, -40),
		canCollide = false,
	})
end

--- The spout under the mouth's left, the slag channel along the plinth, and the mould.
local function buildChannel(m: Model, origin: CFrame)
	local front = BODY_Z + COURSES[1].d / 2
	part(m, origin, "Spout", { 3.2, PLINTH_H + 0.9, front + 0.7 }, { 1.4, 0.6, 1.4 }, COLOR.iron)
	local len = 3.6
	part(m, origin, "ChannelBed", { 3.2, PLINTH_H + 0.15, front + 1.4 + len / 2 }, { 1.6, 0.3, len }, COLOR.iron)
	part(m, origin, "ChannelGlow", { 3.2, PLINTH_H + 0.32, front + 1.4 + len / 2 }, { 1, 0.05, len - 0.2 }, COLOR.molten, {
		canCollide = false,
	})
	part(m, origin, "Mould", { 3.2, PLINTH_H + 0.35, front + 1.4 + len + 0.6 }, { 2.6, 0.7, 1.8 }, COLOR.iron)
	part(m, origin, "MouldSlag", { 3.2, PLINTH_H + 0.72, front + 1.4 + len + 0.6 }, { 2, 0.05, 1.2 }, COLOR.crust, {
		canCollide = false,
	})
end

--- The ramp up the right side to the hopper, so the machine reads as fed from above.
local function buildRamp(m: Model, origin: CFrame, hopperTop: number)
	local x = COURSES[1].w / 2 + 1.6
	local rise = hopperTop - PLINTH_H - 1
	local run = 9
	local length = math.sqrt(rise * rise + run * run)
	local tilt = math.atan2(rise, run)
	part(m, origin, "Ramp", { x, PLINTH_H + rise / 2, BODY_Z + 1.5 }, { 2.4, 0.5, length }, COLOR.iron, {
		rot = CFrame.Angles(tilt, 0, 0),
	})
	for _, side in { -1, 1 } do
		part(m, origin, "RampRail", { x + side * 1.25, PLINTH_H + rise / 2 + 0.5, BODY_Z + 1.5 }, { 0.2, 0.6, length }, COLOR.hazYellow, {
			rot = CFrame.Angles(tilt, 0, 0),
			canCollide = false,
		})
	end
	-- The legs under the ramp's high end.
	part(m, origin, "RampLeg", { x, PLINTH_H + (rise - 0.5) / 2, BODY_Z + 1.5 - run / 2 + 0.6 }, { 0.6, rise - 0.5, 0.6 }, COLOR.iron)
end

--- Two stacks standing on the bottom course's back shoulders, set into the second's sides.
local function buildChimneys(m: Model, origin: CFrame, top: number)
	local base = PLINTH_H + COURSES[1].h
	local h = top + 1.5 - base
	for _, x in { -5.6, 5.6 } do
		local z = BODY_Z - COURSES[1].d / 2 + 1.3
		part(m, origin, "Chimney", { x, base + h / 2, z }, { h, 1.8, 1.8 }, COLOR.basaltDark, {
			shape = "Cylinder",
			rot = R.cylUp,
		})
		part(m, origin, "ChimneyCap", { x, base + h + 0.2, z }, { 0.4, 2.4, 2.4 }, COLOR.crust, {
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
	end
end

--- Cooled slag lumps heaped on the plinth's left.
local function buildSlagPile(m: Model, origin: CFrame)
	local lumps = {
		{ -9.8, 0.9, 1.5, 1.8 },
		{ -8.6, 0.8, 3.2, 1.6 },
		{ -10.4, 0.7, 3.6, 1.4 },
		{ -9.2, 1.9, 2.6, 1.3 },
		{ -11, 0.6, 0.6, 1.2 },
	}
	for index, l in lumps do
		part(m, origin, "SlagLump", { l[1], PLINTH_H + l[2], l[3] }, { l[4], l[4], l[4] }, if index % 2 == 0
			then COLOR.slag
			else COLOR.slagDark, { shape = "Ball" })
	end
end

--- An invisible marker the client lights or sparks from, at `at` (world).
local function marker(m: Model, name: string, at: Vector3, size: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(at)
	p.Color = Color3.fromHex(COLOR.ember)
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = m
end

--- The imported furnace (ServerStorage.StationTemplates.SlagFurnace): its own plinth,
--- fanged mouth, chimney, lava basin and chains. Only the invisible Embers (in the
--- mouth) and SparkPoint (over the chimney's fire) the client flares are added. Returns
--- the part the sign hangs off and the height (above that part) it hangs at.
local function buildImported(m: Model, origin: CFrame, template: Model): (BasePart, number)
	local look = ImportedStation.place(template, m, origin, SlagFurnace.IMPORT_SCALE, "plinth_Node")
	ImportedStation.paint(look, IMPORT_PAINT)
	local _, lookSize = look:GetBoundingBox()

	local mouth, mouthSize = ImportedStation.bounds(look, "mouth_lava")
	if mouth and mouthSize then
		-- Just proud of the lava face, toward the player, so the light spills out.
		marker(m, "Embers", mouth.Position + origin.LookVector * 0.5, Vector3.new(mouthSize.X * 0.8, mouthSize.Y * 0.4, 0.2))
	end
	local fire = ImportedStation.bounds(look, "chimney_fire")
	if fire then
		marker(m, "SparkPoint", fire.Position + Vector3.new(0, 1, 0), Vector3.new(0.2, 0.2, 0.2))
	end

	local plinth = look:FindFirstChild("plinth", true)
	local body = if plinth and plinth:IsA("BasePart") then plinth else look:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	return body, lookSize.Y + 4 - (body.Position.Y - origin.Y)
end

--- Build the furnace under `parent` at `origin` (deck top, facing +Z). `campKey` is its
--- StationId, so a later camp's furnace is its own station.
function SlagFurnace.build(parent: Instance, origin: CFrame, campKey: string): Model
	local m = Instance.new("Model")
	m.Name = SlagFurnace.MODEL_NAME

	local depth = 2 * SlagFurnace.HALF_Z

	local template = ImportedStation.template(SlagFurnace.MODEL_NAME)
	local body: BasePart
	if template then
		local signHeight
		body, signHeight = buildImported(m, origin, template)
		m:SetAttribute("ImportedLook", true)
		Kit.billboard(body, 260, signHeight, "Slag Furnace", nil, nil, 60)
	else
		-- ── Plinth, with hazard tape along its front ──
		local width = 2 * SlagFurnace.HALF_X
		part(m, origin, "Plinth", { 0, PLINTH_H / 2, 0 }, { width, PLINTH_H, depth }, COLOR.plinth, { studs = true })
		local bands = 13
		for i = 0, bands - 1 do
			local w = width / bands
			part(m, origin, "Tape", { -width / 2 + w * (i + 0.5), PLINTH_H / 2, depth / 2 + 0.05 }, { w, 0.6, 0.1 }, if i % 2 == 0
				then COLOR.hazYellow
				else COLOR.hazBlack, { canCollide = false })
		end

		local hopperTop
		body, hopperTop = buildBody(m, origin)
		buildMouth(m, origin)
		buildChannel(m, origin)
		buildRamp(m, origin, hopperTop)
		buildChimneys(m, origin, hopperTop)
		buildSlagPile(m, origin)

		-- Clear of the chimney caps.
		Kit.billboard(body, 260, hopperTop + 6, "Slag Furnace", nil, nil, 60)
	end

	-- ── The station, in front, with its E ──
	local station = part(m, origin, SlagFurnace.STATION_NAME, { 0, 2.5, depth / 2 + 1.5 }, { 1, 1, 1 }, COLOR.steel, {
		transparency = 1,
		canCollide = false,
		attributes = { StationKind = "furnace", StationId = campKey, Radius = SlagFurnace.RADIUS },
	})
	station.CanQuery = false
	station.CanTouch = false
	-- A plain default prompt, like the forge's: the panel is the custom part.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = SlagFurnace.PROMPT_NAME
	prompt.ActionText = "Open"
	prompt.ObjectText = "Slag Furnace"
	prompt.HoldDuration = 0
	-- Inside the station's radius, so the E is never offered from a spot where the server
	-- does not yet count you as at the furnace.
	prompt.MaxActivationDistance = SlagFurnace.RADIUS - 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = station

	m.PrimaryPart = body
	-- What client FurnaceStationController finds the machine by.
	CollectionService:AddTag(m, SlagFurnace.TAG)
	m.Parent = parent
	return m
end

return SlagFurnace
