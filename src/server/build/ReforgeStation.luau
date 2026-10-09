--!strict
--[[
	ReforgeStation.luau — the Reforge Station (Services/ReforgeService, Config/Reforge).
	Built by build/CampSite on the north deck, where the cleansing station used to stand,
	in every site camp whose Config/Camps entry sets `reforge` (Toxic Twilight).

	A FORGE AND AN ANVIL: a squat brick furnace at the back with an ember mouth and a
	chimney, an anvil in front of it with the hammer resting on it, and a quench barrel
	to one side. When the place has ServerStorage.StationTemplates.ReforgeStation, that
	imported model is the look instead (build/ImportedStation).

	AUTHORED FACING +Z (the player walks up from +Z), origin at the deck's top face,
	centred on the machine. Nothing here moves on the server. The strike (the hammer
	swinging, sparks off the anvil, the forge flaring) is
	client/Controllers/ReforgeStationController's, driven off the attributes
	ReforgeService writes on this model.

	NAMED PARTS THE CLIENT READS (keep these names):
	    Hammer         a Model (the import's hammer, or HammerHandle + HammerHead),
	                   pivoted at the handle's end, its Z the swing axis
	    StrikePoint    invisible, on the anvil face, where the sparks fly from
	    Embers         the glow inside the furnace mouth
	    ForgeStation   StationKind = "reforge", StationId = the camp key, "OpenReforge" prompt

	MATTE, LIKE EVERY OTHER PROP (Kit's palette note). The embers read orange by colour,
	not Neon, and there is no standing light; the client lights them only mid-strike.
]]

local CollectionService = game:GetService("CollectionService")

local ImportedStation = require(script.Parent.ImportedStation)
local Kit = require(script.Parent.Kit)

local ReforgeStation = {}

ReforgeStation.MODEL_NAME = "ReforgeStation"
ReforgeStation.STATION_NAME = "ForgeStation"
ReforgeStation.PROMPT_NAME = "OpenReforge"
ReforgeStation.TAG = "ReforgeStation"

--- How far in front of the machine the panel answers, and its footprint.
ReforgeStation.RADIUS = 9
ReforgeStation.HALF_X = 11
ReforgeStation.HALF_Z = 7
--- The imported look is ~0.68 x 0.52 x 0.55 studs as it comes in.
ReforgeStation.IMPORT_SCALE = 30

--- The import's own colours are near-black iron, too dark on Twilight's deck, so every
--- piece is repainted (ImportedStation.paint): darker stone plinth, wood stump and
--- handles, a grey anvil, bright steel tools, a copper-rimmed brazier on glowing coals, a hot ingot and
--- violet runes.
local IMPORT_PAINT: { [string]: ImportedStation.Paint } = {
	plinth = { color = "5E566B" },
	plinth_step = { color = "706880" },
	plinth_block_line = { color = "403A4A" },
	rune_ring = { color = "B57BFF", neon = true },
	rune_glyph = { color = "D2B0FF", neon = true },
	stump = { color = "8B5A34" },
	stump_top = { color = "B07A4C" },
	stump_ring = { color = "8B5A34" },
	stump_band = { color = "7E8893" },
	anvil_foot = { color = "8E847C" },
	anvil_foot_toe = { color = "8E847C" },
	anvil_waist = { color = "9E948C" },
	anvil_body = { color = "AFA49B" },
	anvil_face = { color = "CEC4BA" },
	anvil_heel = { color = "AFA49B" },
	anvil_horn = { color = "AFA49B" },
	horn_step = { color = "9E948C" },
	hardy_hole = { color = "3B4048" },
	pritchel_hole = { color = "3B4048" },
	anvil_rune = { color = "B57BFF", neon = true },
	ingot = { color = "FF7A2A", neon = true },
	ingot_core = { color = "FFC85A", neon = true },
	hammer_handle = { color = "9A6A3E" },
	hammer_grip = { color = "5E3D27" },
	hammer_head = { color = "98A3AF" },
	hammer_face = { color = "C8D1D9" },
	hammer_band = { color = "77818C" },
	brazier_leg = { color = "6F7984" },
	brazier_foot = { color = "6F7984" },
	leg_bracket = { color = "8A95A1" },
	brazier_bowl = { color = "7E8893" },
	brazier_bottom = { color = "5F6872" },
	brazier_rim = { color = "C9783A" },
	coal_bed = { color = "FF5A14", neon = true },
	coal = { color = "3E3539" },
	-- A few coals burn through (exact names win over the "coal" key).
	coal2 = { color = "FF6A1E", neon = true },
	coal5 = { color = "FF8A2E", neon = true },
	coal8 = { color = "FF6A1E", neon = true },
	coal11 = { color = "FF8A2E", neon = true },
	tong_arm = { color = "77818C" },
	tong_jaw = { color = "5F6872" },
	tong_pivot = { color = "C8D1D9" },
	bucket_body = { color = "8B5A34" },
	bucket_floor = { color = "6B4426" },
	bucket_rim = { color = "7E8893" },
	bucket_hoop = { color = "7E8893" },
	bucket_water = { color = "4FB8DA" },
}

local build = Kit.build
local R = Kit.R

local COLOR = {
	plinth = "3A2F45",
	brick = "5A3A34",
	brickDark = "432A26",
	mouth = "1E1716",
	ember = "FF6A1A",
	steel = "59636D",
	steelDark = "3B4048",
	iron = "2E3238",
	wood = "6B4A2E",
	water = "3FA7C9",
	hazYellow = "FFC21A",
	hazBlack = "22252A",
	plate = "22272C",
	forge = "FF8A3D",
}

local PLINTH_H = 1.2
local FURNACE = { w = 12, h = 7, d = 5, z = -3.5 }
local ANVIL_Z = 3
local ANVIL_TOP = PLINTH_H + 3.6

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

local function buildFurnace(m: Model, origin: CFrame): BasePart
	local f = FURNACE
	local front = f.z + f.d / 2
	local body = part(m, origin, "Furnace", { 0, PLINTH_H + f.h / 2, f.z }, { f.w, f.h, f.d }, COLOR.brick, { studs = true })
	-- A darker course along the foot and the crown.
	part(m, origin, "FurnaceFoot", { 0, PLINTH_H + 0.5, f.z }, { f.w + 0.6, 1, f.d + 0.6 }, COLOR.brickDark)
	part(m, origin, "FurnaceCrown", { 0, PLINTH_H + f.h + 0.4, f.z }, { f.w + 0.6, 0.8, f.d + 0.6 }, COLOR.brickDark)

	-- The mouth: a dark recess with the embers sat in it.
	part(m, origin, "Mouth", { 0, PLINTH_H + 2.4, front + 0.05 }, { 5.5, 3, 0.1 }, COLOR.mouth, { canCollide = false })
	part(m, origin, "MouthArch", { 0, PLINTH_H + 4.15, front + 0.2 }, { 6.5, 0.5, 0.4 }, COLOR.brickDark, { canCollide = false })
	part(m, origin, "Embers", { 0, PLINTH_H + 1.4, front + 0.15 }, { 4.6, 1, 0.2 }, COLOR.ember, { canCollide = false })

	-- The nameplate above the arch.
	local plate = part(m, origin, "NamePlate", { 0, PLINTH_H + 5.6, front + 0.06 }, { 8, 1.3, 0.12 }, COLOR.plate, {
		canCollide = false,
	})
	-- Back is +Z, the face the player walks up to (a part's Front is its -Z).
	Kit.surfaceText(plate, Enum.NormalId.Back, "REFORGE", COLOR.forge)

	-- The chimney, back left, with a cap.
	local chimneyH = 7
	part(m, origin, "Chimney", { -3.5, PLINTH_H + f.h + chimneyH / 2, f.z - 0.5 }, { 2.6, chimneyH, 2.6 }, COLOR.brick, {
		studs = true,
	})
	part(m, origin, "ChimneyCap", { -3.5, PLINTH_H + f.h + chimneyH + 0.25, f.z - 0.5 }, { 3.4, 0.5, 3.4 }, COLOR.iron)
	return body
end

--- The StrikePoint and the Hammer lying across an anvil face whose top is `top`, the
--- head at (x, z), the handle out to the left. Its pivot is the handle's far end, so the
--- client swings it from there. `size` scales the hammer.
local function buildHammer(m: Model, origin: CFrame, x: number, top: number, z: number, size: number)
	local strike = part(m, origin, "StrikePoint", { x, top + 0.1, z }, { 0.2, 0.2, 0.2 }, COLOR.steel, {
		transparency = 1,
		canCollide = false,
	})
	strike.CanQuery = false
	strike.CanTouch = false

	local hammer = Instance.new("Model")
	hammer.Name = "Hammer"
	local handleLen = 3.2 * size
	local headY = top + 0.35 * size
	local handle = part(hammer, origin, "HammerHandle", { x - handleLen / 2, headY, z }, { handleLen, 0.35 * size, 0.35 * size }, COLOR.wood, {
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})
	part(hammer, origin, "HammerHead", { x, headY, z }, { 0.9 * size, 0.7 * size, 1.4 * size }, COLOR.steel, {
		canCollide = false,
	})
	hammer.PrimaryPart = handle
	hammer.WorldPivot = origin * CFrame.new(x - handleLen, headY, z)
	hammer.Parent = m
end

local function buildAnvil(m: Model, origin: CFrame)
	-- Stump, waist, face and horn, iron on a wooden block.
	part(m, origin, "AnvilStump", { 0, PLINTH_H + 0.9, ANVIL_Z }, { 1.8, 3.2, 3.2 }, COLOR.wood, {
		shape = "Cylinder",
		rot = R.cylUp,
	})
	part(m, origin, "AnvilFoot", { 0, PLINTH_H + 2.05, ANVIL_Z }, { 3.6, 0.5, 2.2 }, COLOR.iron)
	part(m, origin, "AnvilWaist", { 0, PLINTH_H + 2.65, ANVIL_Z }, { 1.8, 0.7, 1.4 }, COLOR.iron)
	part(m, origin, "AnvilFace", { 0, ANVIL_TOP - 0.35, ANVIL_Z }, { 4.4, 0.7, 2 }, COLOR.steelDark)
	part(m, origin, "AnvilHorn", { 2.9, ANVIL_TOP - 0.35, ANVIL_Z }, { 1.6, 0.7, 0.7 }, COLOR.steelDark, {
		shape = "Cylinder",
		rot = R.cylAlongX,
	})
	part(m, origin, "AnvilHornTip", { 3.7, ANVIL_TOP - 0.35, ANVIL_Z }, { 0.5, 0.5, 0.5 }, COLOR.steelDark, { shape = "Ball" })

	buildHammer(m, origin, -0.6, ANVIL_TOP, ANVIL_Z, 1)
end

local function buildBarrel(m: Model, origin: CFrame)
	local x, z, h = -8, 3, 2.6
	part(m, origin, "QuenchBarrel", { x, PLINTH_H + h / 2, z }, { h, 3, 3 }, COLOR.wood, {
		shape = "Cylinder",
		rot = R.cylUp,
	})
	for _, y in { 0.5, h - 0.5 } do
		part(m, origin, "BarrelHoop", { x, PLINTH_H + y, z }, { 0.3, 3.15, 3.15 }, COLOR.iron, {
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
	end
	part(m, origin, "QuenchWater", { x, PLINTH_H + h + 0.02, z }, { 0.1, 2.6, 2.6 }, COLOR.water, {
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})
end

--- A short rack of finished ingots on the right, so the forge reads as a working one.
local function buildIngots(m: Model, origin: CFrame)
	local x, z = 8, 2.5
	part(m, origin, "IngotRack", { x, PLINTH_H + 0.9, z }, { 3.6, 1.8, 2.6 }, COLOR.wood)
	for i = 0, 2 do
		part(m, origin, "Ingot", { x - 1.1 + i * 1.1, PLINTH_H + 2.05, z }, { 0.9, 0.5, 2 }, if i == 1 then COLOR.forge else COLOR.steel, {
			canCollide = false,
		})
	end
end

--- The imported forge (ServerStorage.StationTemplates.ReforgeStation): its own plinth,
--- stump, anvil, hammer, brazier, tongs and bucket. Its hammer is lifted out as the
--- Hammer the client swings; a StrikePoint under its head and invisible Embers on the
--- brazier are added. Returns the
--- part the sign hangs off and the height (above that part) it hangs at.
local function buildImported(m: Model, origin: CFrame, template: Model): (BasePart, number)
	local look = ImportedStation.place(template, m, origin, ReforgeStation.IMPORT_SCALE, "plinth_Node")
	ImportedStation.paint(look, IMPORT_PAINT)
	local _, lookSize = look:GetBoundingBox()

	local anvil, anvilSize = ImportedStation.bounds(look, "anvil")
	local hammer = look:FindFirstChild("hammer", true)
	local head = hammer and hammer:FindFirstChild("hammer_head", true)
	local grip = hammer and hammer:FindFirstChild("hammer_grip", true)
	if hammer and hammer:IsA("Model") and head and head:IsA("BasePart") and grip and grip:IsA("BasePart") then
		-- The import's own hammer becomes the one the client swings: X along the handle
		-- (grip to head, level), Y up, pivot at the grip's far end, so a turn about its Z
		-- lifts the head.
		local flat = (head.Position - grip.Position) * Vector3.new(1, 0, 1)
		local along = if flat.Magnitude > 1e-3 then flat.Unit else origin.RightVector
		local reach = math.max(grip.Size.X, grip.Size.Z) / 2
		hammer.Name = "Hammer"
		hammer.WorldPivot = CFrame.fromMatrix(grip.Position - along * reach, along, Vector3.yAxis)
		hammer.Parent = m
		for _, d in hammer:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
			end
		end

		local strike = Instance.new("Part")
		strike.Name = "StrikePoint"
		strike.Size = Vector3.new(0.2, 0.2, 0.2)
		strike.CFrame = CFrame.new(head.Position + Vector3.new(0, head.Size.Y / 2 + 0.1, 0))
		strike.Transparency = 1
		strike.Anchored = true
		strike.CanCollide = false
		strike.CanQuery = false
		strike.CanTouch = false
		strike.Parent = m
	elseif anvil and anvilSize then
		if hammer then
			hammer:Destroy()
		end
		local at = origin:PointToObjectSpace(anvil.Position)
		-- The head sits a little off-centre, towards the horn's root, like the old one.
		buildHammer(m, origin, at.X - anvilSize.X * 0.1, at.Y + anvilSize.Y / 2, at.Z, 1.6)
	end
	local brazier, brazierSize = ImportedStation.bounds(look, "forge_brazier")
	if brazier and brazierSize then
		-- The client's flare: a light and Neon on this; invisible, the brazier is the look.
		local at = origin:PointToObjectSpace(brazier.Position)
		local embers = part(m, origin, "Embers", { at.X, at.Y + brazierSize.Y / 2, at.Z }, { brazierSize.X * 0.6, 0.2, brazierSize.Z * 0.6 }, COLOR.ember, {
			transparency = 1,
			canCollide = false,
		})
		embers.CanQuery = false
		embers.CanTouch = false
	end

	local plinth = look:FindFirstChild("plinth", true)
	local body = if plinth and plinth:IsA("BasePart") then plinth else look:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	return body, lookSize.Y + 4 - (body.Position.Y - origin.Y)
end

--- Build the forge under `parent` at `origin` (deck top, facing +Z). `campKey` is its
--- StationId, so a later camp's forge is its own station.
function ReforgeStation.build(parent: Instance, origin: CFrame, campKey: string): Model
	local m = Instance.new("Model")
	m.Name = ReforgeStation.MODEL_NAME
	local depth = 2 * ReforgeStation.HALF_Z

	local template = ImportedStation.template(ReforgeStation.MODEL_NAME)
	local body: BasePart
	if template then
		local signHeight
		body, signHeight = buildImported(m, origin, template)
		m:SetAttribute("ImportedLook", true)
		Kit.billboard(body, 260, signHeight, "Reforge Station", nil, nil, 60)
	else
		-- ── Plinth, with hazard tape along its front ──
		local width = 2 * ReforgeStation.HALF_X
		part(m, origin, "Plinth", { 0, PLINTH_H / 2, 0 }, { width, PLINTH_H, depth }, COLOR.plinth, { studs = true })
		local bands = 11
		for i = 0, bands - 1 do
			local w = width / bands
			part(m, origin, "Tape", { -width / 2 + w * (i + 0.5), PLINTH_H / 2, depth / 2 + 0.05 }, { w, 0.6, 0.1 }, if i % 2 == 0
				then COLOR.hazYellow
				else COLOR.hazBlack, { canCollide = false })
		end

		body = buildFurnace(m, origin)
		buildAnvil(m, origin)
		buildBarrel(m, origin)
		buildIngots(m, origin)

		-- Clear of the chimney's cap (~16 up).
		Kit.billboard(body, 260, FURNACE.h / 2 + 11, "Reforge Station", nil, nil, 60)
	end

	-- ── The station, in front, with its E ──
	local station = part(m, origin, ReforgeStation.STATION_NAME, { 0, 2.5, depth / 2 + 1.5 }, { 1, 1, 1 }, COLOR.steel, {
		transparency = 1,
		canCollide = false,
		attributes = { StationKind = "reforge", StationId = campKey, Radius = ReforgeStation.RADIUS },
	})
	station.CanQuery = false
	station.CanTouch = false
	-- A plain default prompt, like the reactor's: the panel is the custom part.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = ReforgeStation.PROMPT_NAME
	prompt.ActionText = "Open"
	prompt.ObjectText = "Reforge Station"
	prompt.HoldDuration = 0
	-- Inside the station's radius, so the E is never offered from a spot where the server
	-- does not yet count you as at the forge.
	prompt.MaxActivationDistance = ReforgeStation.RADIUS - 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = station

	m.PrimaryPart = body
	-- What client ReforgeStationController finds the machine by.
	CollectionService:AddTag(m, ReforgeStation.TAG)
	m.Parent = parent
	return m
end

return ReforgeStation
