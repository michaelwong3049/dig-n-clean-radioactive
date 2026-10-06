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

	EVERYTHING IS AUTHORED AT SCALE 1 AND BLOWN UP BY `SCALE` in part(), so the numbers
	below stay readable. The model carries it as its `Scale` attribute; the client sizes
	the nukes it drops and lifts by that. No text on the machine: the E prompt names it.
]]

local CollectionService = game:GetService("CollectionService")

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

--- Build the reactor under `parent` at `origin` (deck top, facing +Z). `campKey` is
--- its StationId, so a later camp's reactor is its own station.
function MergeReactor.build(parent: Instance, origin: CFrame, campKey: string): Model
	local m = Instance.new("Model")
	m.Name = MergeReactor.MODEL_NAME

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

	-- ── The station, in front, with its E ──
	local station = part(m, origin, MergeReactor.STATION_NAME, { 0, 2.5, depth / 2 + 1.5 }, { 1, 1, 1 }, COLOR.steel, {
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
