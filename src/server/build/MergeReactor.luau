--!strict
--[[
	MergeReactor.luau — the Merge Reactor machine (Services/MergeService,
	Config/Merge). Built by build/CampSite on its own deck south of the plaza, in every
	site camp whose Config/Camps entry sets `mergeReactor` (Toxic Twilight).

	PICKED FROM BROWSER MOCKUPS (option 1, "Triple Hopper Reactor", over a Fusion Press
	and a Tri-Core Centrifuge): three glass hoppers of violet ooze on stilts, piped down
	into a squat reactor body under a glass dome, where the result rises on a lift.

	AUTHORED FACING +Z (the player walks up from +Z), origin at the deck's top face,
	centred on the machine. Nothing here moves on the server. The idle bubbling and the
	whole merge (nukes dropping into the hoppers, the core charging, the result rising)
	are client/Controllers/MergeReactorController's, driven off the attributes
	MergeService writes on this model.

	NAMED PARTS THE CLIENT READS (keep these names):
	    Hopper1..3    the glass hopper bodies (left, back-centre, right)
	    Ooze1..3      the fill inside each hopper
	    Drop1..3      invisible points above each hopper's mouth, where a nuke appears
	    CoreGlow      the ball inside the dome that charges
	    Dome          the glass dome
	    LiftPad       the plate the result rises from
	    MergeStation  StationKind = "merge", StationId = the camp key, "OpenMerge" prompt

	MATTE, LIKE EVERY OTHER PROP (Kit's palette note). The ooze reads violet by colour,
	not Neon, and there is no standing light; the client lights the core only while a
	merge is running. The ooze's living look (sheen, drifting motes, bubbles, slosh) is
	the client's too, so it shows on a world built before it existed.

	THE IMPORTED LOOK. When the place has ServerStorage.StationTemplates.MergeReactor
	(build/ImportedStation), that model is the machine instead: a hex deck, three caged
	glass tanks on legs hosed into a teal core under a glass dome, the orb on a yellow
	pedestal inside it. It is repainted to the user's reference render (IMPORT_PAINT),
	its tank liquid becomes Ooze1..3, its orb CoreGlow, and Drop1..3 / LiftPad are added
	as invisible markers, so the client's show runs on it unchanged.

	EVERYTHING IS AUTHORED AT SCALE 1 AND BLOWN UP BY `SCALE` in part(), so the numbers
	below stay readable. The model carries it as its `Scale` attribute; the client sizes
	the nukes it drops and lifts by that. No text on the machine: the E prompt names it.
]]

local CollectionService = game:GetService("CollectionService")

local ImportedStation = require(script.Parent.ImportedStation)
local Kit = require(script.Parent.Kit)

local MergeReactor = {}

MergeReactor.MODEL_NAME = "MergeReactor"
MergeReactor.STATION_NAME = "MergeStation"
MergeReactor.PROMPT_NAME = "OpenMerge"
MergeReactor.TAG = "MergeReactor"

--- How much bigger than its authored size the machine is built. At 1.5 it fills the
--- deck (CampSite MERGE_DECK_HALF_X 18) to within a couple of studs either side.
MergeReactor.SCALE = 1.5
local SCALE = MergeReactor.SCALE

--- How far in front of the machine the panel answers, and the footprint CampSite
--- sizes the deck to.
MergeReactor.RADIUS = 9
MergeReactor.HALF_X = 11 * SCALE
MergeReactor.HALF_Z = 7 * SCALE

--- The imported look is ~0.86 x 0.48 x 0.75 studs as it comes in; this fills the deck
--- (CampSite gives the reactor a 44 x 40 one) with ~6 studs clear all round.
MergeReactor.IMPORT_SCALE = 36

--- The import's colours, repainted to the user's reference render (2026-10-08): a
--- navy-violet hex deck with pink-violet neon conduits, dark teal tanks and core,
--- silver rods and rings, lavender glass over pink-lavender liquid, a chrome dome over
--- a pink orb on a glowing yellow pedestal, and a cyan screen with pink/yellow/red
--- buttons over a gold hazard band.
local GLASS = 0.65
local IMPORT_PAINT: { [string]: ImportedStation.Paint } = {
	deck_base = { color = "1E1A33" },
	deck_top = { color = "3A2580" },
	deck_trim = { color = "C77DFF", neon = true },
	deck_bolt = { color = "D7DCE6" },
	floor_conduit = { color = "C77DFF", neon = true },
	under_lamp = { color = "232634" },
	under_lamp_glow = { color = "B57BFF", neon = true },

	tank_foot_plate = { color = "1F4140" },
	tank_leg = { color = "234A49" },
	leg_brace = { color = "1F4140" },
	tank_base_collar = { color = "2A5755" },
	tank_cap = { color = "234A49" },
	tank_cap_top = { color = "2A5755" },
	cap_bolt = { color = "14171E" },
	cap_valve = { color = "D99BFF" },
	cap_valve_wheel = { color = "E3A8FF" },
	collar_ring = { color = "9C8CFF" },
	tank_rod = { color = "C9CED8" },
	tank_band = { color = "DDE1EA" },
	tank_glass = { color = "B8A2FF", transparency = GLASS },
	tank_liquid = { color = "B47EFF" },
	tank_liquid_core = { color = "F2CCFF", neon = true },

	feed_hose = { color = "3F4A66" },
	feed_hose_glow = { color = "B57BFF", neon = true },
	core_port = { color = "232634" },
	core_body = { color = "1F403F" },
	core_skirt = { color = "234A49" },
	core_collar = { color = "2A5755" },
	core_collar_ring = { color = "C9CED8" },
	core_vent_glow = { color = "B57BFF", neon = true },

	dome_base = { color = "B9C1D2" },
	dome_glass = { color = "ECE8FF", transparency = 0.7 },
	dome_cap = { color = "C9CED8" },
	pedestal_ring = { color = "FFD84A", neon = true },
	pedestal_disk = { color = "FFEB80", neon = true },
	merge_orb = { color = "F2A8F0" },
	orb_core = { color = "FFD8FA", neon = true },
	orb_claw = { color = "C9CED8" },
	claw_tip = { color = "FF8AE6" },
	gyro_ring_ = { color = "D7A8FF" },

	lever_base = { color = "14171E" },
	lever_arm = { color = "2A2D3A" },
	lever_knob = { color = "E07BFF" },
	lever_knob2 = { color = "FFD84A" },
	panel_bezel = { color = "1C2030" },
	panel_screen = { color = "5FF2E8", neon = true },
	screen_bar = { color = "1B3F4A" },
	panel_button = { color = "E07BFF" },
	panel_button2 = { color = "FFD84A" },
	panel_button3 = { color = "FF4A5A" },
	panel_slider_track = { color = "2A2D3A" },
	panel_slider = { color = "C9CED8" },
	mr_band = { color = "E8B43C" },
	mr_band_stripe_ = { color = "14171E" },
}

local build = Kit.build
local R = Kit.R

local COLOR = {
	body = "3E2A5C",
	trim = "57407E",
	pipe = "7C5AB0",
	ooze = "A855FF",
	glass = "CFE8FF",
	dome = "D9C9FF",
	steel = "59636D",
	hazYellow = "FFC21A",
	hazBlack = "22252A",
	plate = "22272C",
	gold = "E8C33C",
}

local PLINTH_H = 1.2
local CORE = { w = 10, h = 5, d = 7, z = 0.5 }
local CORE_TOP = PLINTH_H + CORE.h
local DOME_D = 7

--- One hopper: x/z of its axis, and the height of its glass body's foot.
local HOPPERS = {
	{ x = -8, z = -1, foot = 7.2 },
	{ x = 0, z = -4.6, foot = 9.2 },
	{ x = 8, z = -1, foot = 7.2 },
}
local HOPPER_D = 4.5
local HOPPER_H = 3.5
local NECK_D = 2
local NECK_H = 1.2
local LEG_D = 0.9
local LEG_SPREAD = 1.9
local PIPE_D = 1.2
local PIPE_Y = 4 -- the elbow height, where every pipe turns into the core

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
		pos = { pos[1] * SCALE, pos[2] * SCALE, pos[3] * SCALE },
		size = { size[1] * SCALE, size[2] * SCALE, size[3] * SCALE },
		color = color,
		material = "SmoothPlastic",
	}
	for key, value in extra or {} do
		spec[key] = value
	end
	return build(parent, origin, spec)
end

--- A pipe run between two points on one axis, with a ball at the far end.
local function pipe(parent: Instance, origin: CFrame, a: Vector3, b: Vector3)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local vertical = math.abs(b.Y - a.Y) > 0.01
	local alongZ = math.abs(b.Z - a.Z) > 0.01
	part(parent, origin, "Pipe", { mid.X, mid.Y, mid.Z }, { length, PIPE_D, PIPE_D }, COLOR.pipe, {
		shape = "Cylinder",
		rot = if vertical then R.cylUp elseif alongZ then R.cylAlongZ else R.cylAlongX,
	})
	part(parent, origin, "PipeJoint", { b.X, b.Y, b.Z }, { PIPE_D * 1.3, PIPE_D * 1.3, PIPE_D * 1.3 }, COLOR.trim, {
		shape = "Ball",
	})
end

local function buildHopper(m: Model, origin: CFrame, index: number)
	local h = HOPPERS[index]
	local bodyY = h.foot + HOPPER_H / 2
	local neckY = h.foot - NECK_H / 2

	-- Two stilts either side of the pipe, plinth to the glass.
	local legH = h.foot - PLINTH_H
	for _, side in { -1, 1 } do
		part(m, origin, "HopperLeg", { h.x + side * LEG_SPREAD, PLINTH_H + legH / 2, h.z }, { legH, LEG_D, LEG_D }, COLOR.trim, {
			shape = "Cylinder",
			rot = R.cylUp,
		})
	end
	-- A collar round the glass's foot, carried by the stilts.
	part(m, origin, "HopperCollar", { h.x, h.foot - 0.1, h.z }, { 0.5, HOPPER_D + 0.4, HOPPER_D + 0.4 }, COLOR.steel, {
		shape = "Cylinder",
		rot = R.cylUp,
	})

	-- See-through SmoothPlastic, NOT Glass: Roblox does not draw a transparent part
	-- behind Glass, so a Glass hopper hides its own ooze. The ooze is opaque for the
	-- same reason.
	part(m, origin, `Hopper{index}`, { h.x, bodyY, h.z }, { HOPPER_H, HOPPER_D, HOPPER_D }, COLOR.glass, {
		shape = "Cylinder",
		rot = R.cylUp,
		transparency = 0.7,
		canCollide = false,
	})
	part(m, origin, `Ooze{index}`, { h.x, h.foot + 1.15, h.z }, { 2.2, HOPPER_D - 0.4, HOPPER_D - 0.4 }, COLOR.ooze, {
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})
	part(m, origin, "HopperRim", { h.x, h.foot + HOPPER_H + 0.1, h.z }, { 0.35, HOPPER_D + 0.4, HOPPER_D + 0.4 }, COLOR.steel, {
		shape = "Cylinder",
		rot = R.cylUp,
	})
	part(m, origin, "HopperNeck", { h.x, neckY, h.z }, { NECK_H, NECK_D, NECK_D }, COLOR.ooze, {
		shape = "Cylinder",
		rot = R.cylUp,
	})

	local drop = part(m, origin, `Drop{index}`, { h.x, h.foot + HOPPER_H + 3, h.z }, { 0.2, 0.2, 0.2 }, COLOR.glass, {
		transparency = 1,
		canCollide = false,
	})
	drop.CanQuery = false
	drop.CanTouch = false

	-- The pipe: straight down out of the neck to the elbow, then into the core's nearest
	-- face (its side for the two outer hoppers, its back for the centre one).
	local top = Vector3.new(h.x, h.foot - NECK_H, h.z)
	local elbow = Vector3.new(h.x, PIPE_Y, h.z)
	pipe(m, origin, top, elbow)
	local into = if h.x < 0
		then Vector3.new(-CORE.w / 2, PIPE_Y, h.z)
		elseif h.x > 0 then Vector3.new(CORE.w / 2, PIPE_Y, h.z)
		else Vector3.new(h.x, PIPE_Y, CORE.z - CORE.d / 2)
	pipe(m, origin, elbow, into)
end

--- The part-built machine, for a place without the imported template. Returns its body.
local function buildParts(m: Model, origin: CFrame): BasePart
	-- ── Plinth, with hazard tape along its front ──
	-- Authored (unscaled) footprint: part() scales it.
	local depth = 2 * MergeReactor.HALF_Z / SCALE
	local width = 2 * MergeReactor.HALF_X / SCALE
	part(m, origin, "Plinth", { 0, PLINTH_H / 2, 0 }, { width, PLINTH_H, depth }, COLOR.trim, { studs = true })
	local bands = 11
	for i = 0, bands - 1 do
		local w = width / bands
		part(m, origin, "Tape", { -width / 2 + w * (i + 0.5), PLINTH_H / 2, depth / 2 + 0.05 }, { w, 0.6, 0.1 }, if i % 2 == 0
			then COLOR.hazYellow
			else COLOR.hazBlack, { canCollide = false })
	end

	-- ── The reactor body ──
	local body = part(m, origin, "CoreBody", { 0, PLINTH_H + CORE.h / 2, CORE.z }, { CORE.w, CORE.h, CORE.d }, COLOR.body)
	local front = CORE.z + CORE.d / 2
	part(m, origin, "CoreBand", { 0, PLINTH_H + 1.4, front + 0.06 }, { CORE.w - 1.5, 0.9, 0.12 }, COLOR.gold, { canCollide = false })
	-- A vent grille where the name plate was: three dark slats.
	for i = 0, 2 do
		part(m, origin, "Vent", { 0, PLINTH_H + 2.8 + i * 0.55, front + 0.06 }, { CORE.w - 3, 0.3, 0.12 }, COLOR.plate, {
			canCollide = false,
		})
	end
	-- Corner bolts on the front face.
	for _, sx in { -1, 1 } do
		for _, sy in { 0.7, CORE.h - 0.7 } do
			part(m, origin, "Bolt", { sx * (CORE.w / 2 - 0.6), PLINTH_H + sy, front + 0.1 }, { 0.2, 0.5, 0.5 }, COLOR.steel, {
				shape = "Cylinder",
				rot = R.cylAlongZ,
				canCollide = false,
			})
		end
	end

	-- ── The dome, and what charges and rises inside it ──
	part(m, origin, "DomeRim", { 0, CORE_TOP + 0.15, CORE.z }, { 0.4, DOME_D + 0.7, DOME_D + 0.7 }, COLOR.steel, {
		shape = "Cylinder",
		rot = R.cylUp,
	})
	part(m, origin, "LiftPad", { 0, CORE_TOP + 0.45, CORE.z }, { 0.3, 3, 3 }, COLOR.gold, {
		shape = "Cylinder",
		rot = R.cylUp,
	})
	part(m, origin, "CoreGlow", { 0, CORE_TOP + 1.9, CORE.z }, { 2.4, 2.4, 2.4 }, COLOR.ooze, {
		shape = "Ball",
		canCollide = false,
	})
	-- Half-sunk into the body, so only the upper hemisphere shows. SmoothPlastic, not
	-- Glass, for the same reason as the hoppers.
	part(m, origin, "Dome", { 0, CORE_TOP, CORE.z }, { DOME_D, DOME_D, DOME_D }, COLOR.dome, {
		shape = "Ball",
		transparency = 0.72,
		canCollide = false,
	})

	for index = 1, #HOPPERS do
		buildHopper(m, origin, index)
	end

	return body
end

--- An invisible, non-colliding marker part at `cframe`.
local function marker(parent: Instance, name: string, cframe: CFrame, size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

--- Swap the painted mesh `found` for a plain primitive called `name`, filling the same
--- box: an upright Cylinder (turned so its height is Size.X, as the client reads it) or
--- a Ball. The client resizes and recolours these, which a mesh would not follow.
local function primitive(found: BasePart, name: string, shape: Enum.PartType, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Material = Enum.Material.SmoothPlastic
	p.Color = found.Color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local s = found.Size
	if shape == Enum.PartType.Cylinder then
		local across = math.max(s.X, s.Z)
		p.Size = Vector3.new(s.Y, across, across)
		p.CFrame = CFrame.new(found.Position) * R.cylUp
	else
		p.Size = Vector3.one * math.max(s.X, s.Y, s.Z)
		p.CFrame = CFrame.new(found.Position)
	end
	-- What the client flashes from and restores to (it defaults to the old violet).
	p:SetAttribute("RestColor", p.Color)
	p.Parent = parent
	found:Destroy()
	return p
end

--- The imported reactor (ServerStorage.StationTemplates.MergeReactor), placed, painted
--- and given the parts the client reads. Returns its core body and how far in front of
--- origin the deck's front edge is (studs).
local function buildImported(m: Model, origin: CFrame, template: Model): (BasePart, number)
	local look = ImportedStation.place(template, m, origin, MergeReactor.IMPORT_SCALE, "reactor_core")
	ImportedStation.paint(look, IMPORT_PAINT)

	for index = 1, #HOPPERS do
		local tank = look:FindFirstChild(`merge_tank_{index}`, true)
		if tank == nil or not tank:IsA("Model") then
			continue
		end
		for _, d in tank:GetDescendants() do
			if d:IsA("BasePart") and string.match(d.Name, "^tank_liquid%d*$") then
				primitive(d, `Ooze{index}`, Enum.PartType.Cylinder, m)
				break
			end
		end
		local box, size = tank:GetBoundingBox()
		marker(m, `Drop{index}`, CFrame.new(box.Position + Vector3.new(0, size.Y / 2 + 2, 0)), Vector3.one * 0.2)
	end

	local orb = look:FindFirstChild("merge_orb", true)
	if orb and orb:IsA("BasePart") then
		primitive(orb, "CoreGlow", Enum.PartType.Ball, m)
	end
	local disk = look:FindFirstChild("pedestal_disk", true)
	if disk and disk:IsA("BasePart") then
		local across = math.max(disk.Size.X, disk.Size.Z)
		marker(m, "LiftPad", CFrame.new(disk.Position) * R.cylUp, Vector3.new(disk.Size.Y, across, across))
	end

	local deck, deckSize = ImportedStation.bounds(look, "deck_base")
	local front = if deck and deckSize
		then origin:PointToObjectSpace(deck.Position).Z + deckSize.Z / 2
		else MergeReactor.HALF_Z
	local body = look:FindFirstChild("core_body", true)
	if body and body:IsA("BasePart") then
		return body, front
	end
	return look:FindFirstChildWhichIsA("BasePart", true) :: BasePart, front
end

--- Build the reactor under `parent` at `origin` (deck top, facing +Z). `campKey` is
--- its StationId, so a later camp's reactor is its own station.
function MergeReactor.build(parent: Instance, origin: CFrame, campKey: string): Model
	local m = Instance.new("Model")
	m.Name = MergeReactor.MODEL_NAME

	local template = ImportedStation.template(MergeReactor.MODEL_NAME)
	local body: BasePart
	local stationZ: number
	if template then
		local front
		body, front = buildImported(m, origin, template)
		stationZ = front / SCALE + 1.5
		m:SetAttribute("ImportedLook", true)
	else
		body = buildParts(m, origin)
		stationZ = MergeReactor.HALF_Z / SCALE + 1.5
	end

	-- ── The station, in front, with its E ──
	local station = part(m, origin, MergeReactor.STATION_NAME, { 0, 2.5, stationZ }, { 1, 1, 1 }, COLOR.steel, {
		transparency = 1,
		canCollide = false,
		attributes = { StationKind = "merge", StationId = campKey, Radius = MergeReactor.RADIUS },
	})
	station.CanQuery = false
	station.CanTouch = false
	-- A plain default prompt, like the locker's: the panel is the custom part.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = MergeReactor.PROMPT_NAME
	prompt.ActionText = "Open"
	prompt.ObjectText = "Merge Reactor"
	prompt.HoldDuration = 0
	-- Inside the station's radius, so the E is never offered from a spot where the server
	-- does not yet count you as at the reactor.
	prompt.MaxActivationDistance = MergeReactor.RADIUS - 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = station

	m.PrimaryPart = body
	m:SetAttribute("Scale", SCALE)
	-- What client MergeReactorController finds the machine by.
	CollectionService:AddTag(m, MergeReactor.TAG)
	m.Parent = parent
	return m
end

return MergeReactor
