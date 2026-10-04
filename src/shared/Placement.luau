--!strict
--[[
	Placement.luau — where a nuke may stand on a base's open floor.

	PURE PLOT-LOCAL MATH, SHARED BY BOTH SIDES. The client's placement ghost asks
	`fits` to paint itself green or red; ExhibitService asks the same function before it
	saves a spot, so the two can only disagree by the model-measuring slack below. Every
	position here is in the plot's own local space (x across, z from the entrance at -Z
	to the back fence at +Z), the same frame build/Plots builds a pad in, so a save made
	on one physical plot lands in the same spot on any other.

	A NUKE IS A CIRCLE. Displayed nukes turn slowly on the spot (StationMotion "hover"),
	so the space one needs is the circle its footprint sweeps: half the diagonal of its
	horizontal bounding box (`radiusOf`). Two nukes fit side by side when their circles
	sit GAP apart, so there is always room to walk between them.

	THE OPEN FLOOR (`area`) is everything behind the entrance strip (where the washer,
	treadmill and locker stand, and the player spawns) and inside the side and back
	fences. Its back edge moves out with Config/BaseUpgrades.extraDepth, the same number
	build/Plots moves the back fence by.
]]

local BaseUpgrades = require(script.Parent.Config.BaseUpgrades)

local Placement = {}

--- Clear studs between two nukes' circles.
Placement.GAP = 2
--- How far the server lets a client's spot overlap before it refuses (models measured
--- on two machines can differ by a hair; a refusal for 0.1 stud would feel broken).
Placement.SLACK = 0.25
--- The smallest circle a nuke is given, so a tiny find still keeps its card readable.
Placement.MIN_RADIUS = 1.5

--- The level-0 open floor, plot-local. Matches build/Plots: the pad is 66 wide
--- (fence on +/-33) and its back fence stands at z 56; the entrance strip runs to z -26
--- and PlotSpawn sits at z -24, so the floor starts just behind it.
Placement.AREA = {
	halfWidth = 31.5,
	minZ = -20,
	maxZ = 54.5,
}

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Spot = { x: number, z: number, r: number }

--- The open floor of a base at upgrade `level`.
function Placement.area(level: number?): Rect
	local a = Placement.AREA
	return {
		minX = -a.halfWidth,
		maxX = a.halfWidth,
		minZ = a.minZ,
		maxZ = a.maxZ + BaseUpgrades.extraDepth(level),
	}
end

--- The circle radius for a horizontal bounding box `sizeX` x `sizeZ`.
function Placement.radiusOf(sizeX: number, sizeZ: number): number
	return math.max(Placement.MIN_RADIUS, math.sqrt(sizeX * sizeX + sizeZ * sizeZ) / 2)
end

--- Whether a circle of radius `r` at (x, z) lies wholly on `rect`.
function Placement.inside(rect: Rect, x: number, z: number, r: number, slack: number?): boolean
	local s = slack or 0
	return x - r >= rect.minX - s and x + r <= rect.maxX + s and z - r >= rect.minZ - s and z + r <= rect.maxZ + s
end

--- Whether a circle of radius `r` at (x, z) keeps GAP from every spot in `others`.
--- `skip` is an index into `others` to ignore (a nuke being moved).
function Placement.clear(others: { Spot }, x: number, z: number, r: number, slack: number?, skip: number?): boolean
	local s = slack or 0
	for i, o in others do
		if i ~= skip then
			local need = r + o.r + Placement.GAP - s
			local dx, dz = x - o.x, z - o.z
			if dx * dx + dz * dz < need * need then
				return false
			end
		end
	end
	return true
end

--- Why a spot is refused, or nil when it fits.
function Placement.why(rect: Rect, others: { Spot }, x: number, z: number, r: number, slack: number?, skip: number?): string?
	if x ~= x or z ~= z then
		return "that isn't a spot"
	end
	if not Placement.inside(rect, x, z, r, slack) then
		return "that's off your base"
	end
	if not Placement.clear(others, x, z, r, slack, skip) then
		return "too close to another nuke"
	end
	return nil
end

function Placement.fits(rect: Rect, others: { Spot }, x: number, z: number, r: number, slack: number?, skip: number?): boolean
	return Placement.why(rect, others, x, z, r, slack, skip) == nil
end

--- The first free spot for a circle of radius `r`, scanning the floor back row first,
--- left to right, on a 1-stud grid — what Equip Best uses so auto-placed nukes fill the
--- base from the back fence forward in tidy rows. nil when nothing fits.
function Placement.firstFree(rect: Rect, others: { Spot }, r: number): (number?, number?)
	local z = rect.maxZ - r
	while z >= rect.minZ + r do
		local x = rect.minX + r
		while x <= rect.maxX - r do
			if Placement.clear(others, x, z, r) then
				return x, z
			end
			x += 1
		end
		z -= 1
	end
	return nil, nil
end

return Placement
