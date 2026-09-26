--!strict
--[[
	BiomeKit.luau — the shared parts and placement helpers for the far biomes, Stages 7-12.

	    used by build/CinderField, CobaltShelf, GlassBarrens, SulfurFlats, BloodrockRift
	    and GroundZero, each called from build/Scenery's buildStageScenery

	Every one of those six fields keeps build/Scenery's two standing rules for anything
	over a dig plate, even though the far stages have no nukes stocked yet (dig is OFF out
	there until they do, see Config/Stages): every part here is CanCollide/CanQuery/
	CanTouch false, so a player walks through it and FieldController's range-ring raycast
	and DigService's burial both pass straight to the real plate underneath; and anything
	that stands up keeps off the walk lane down z = 0 (`LANE_HALF`, the same width
	build/FieldLitter clears), so the route east through the chain never reads blocked.

	STUDS ON THE SOLID STUFF, SMOOTH ON THE REST (the keep-stud-texture call): rock,
	crust, wood and concrete are studded Plastic; glass, liquid, metal and anything that
	glows are smooth.

	GLOW, ON REQUEST FOR THE FAR BIOMES ONLY: Neon is allowed on the HOT bits — embers,
	lava, the rift's floor, acid, coolant — and nothing else. Lights are few (`glow`),
	shadows off, the same call every light on a field makes. Particles are few and slow
	(`smoke`), the budget Stage 6's crater vents set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local BiomeKit = {}

--- Half-width of the walk lane down every stage's centreline (world z = 0). Matches
--- build/FieldLitter's LANE_HALF so the whole chain clears one lane width.
BiomeKit.LANE_HALF = 16

--- Clear of the plate's edges: the corridor walls and the seam border strips.
BiomeKit.EDGE_MARGIN = 7

export type Field = {
	id: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	cx: number,
	groundY: number,
}

function BiomeKit.field(stageId: number, groundY: number): Field
	local minX, minZ, maxX, maxZ = Stages.bounds(stageId)
	local m = BiomeKit.EDGE_MARGIN
	return {
		id = stageId,
		minX = minX + m,
		maxX = maxX - m,
		minZ = minZ + m,
		maxZ = maxZ - m,
		cx = (minX + maxX) / 2,
		groundY = groundY,
	}
end

function BiomeKit.onLane(z: number, pad: number?): boolean
	return math.abs(z) < BiomeKit.LANE_HALF + (pad or 0)
end

--- Clamp a point into the field (a thrown piece walking off the plate edge is the bug
--- build/CoolantField's spill tongues hit first).
function BiomeKit.clamp(f: Field, x: number, z: number, inset: number?): (number, number)
	local i = inset or 0
	return math.clamp(x, f.minX + i, f.maxX - i), math.clamp(z, f.minZ + i, f.maxZ - i)
end

-- ── Colour ─────────────────────────────────────────────────────────────────────

function BiomeKit.hex(h: string): Color3
	return Color3.fromHex(h)
end

function BiomeKit.pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

--- `c` pushed toward black (k < 0) or white (k > 0) by |k|.
function BiomeKit.shade(c: Color3, k: number): Color3
	if k < 0 then
		return c:Lerp(Color3.new(0, 0, 0), -k)
	end
	return c:Lerp(Color3.new(1, 1, 1), k)
end

-- ── Parts ──────────────────────────────────────────────────────────────────────

export type PartOpts = {
	studs: boolean?,
	neon: boolean?,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	shadow: boolean?,
	shape: Enum.PartType?,
}

local FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function finish(p: BasePart, name: string, cf: CFrame, size: Vector3, color: Color3, opts: PartOpts?, parent: Instance)
	local o: PartOpts = opts or {}
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if o.neon then
		p.Material = Enum.Material.Neon
		p.CastShadow = false
	elseif o.studs then
		-- Studs only render on Plastic.
		p.Material = Enum.Material.Plastic
		for _, face in FACES do
			(p :: any)[face] = Enum.SurfaceType.Studs
		end
	else
		p.Material = o.material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	if o.transparency then
		p.Transparency = o.transparency
	end
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	if o.shadow == false then
		p.CastShadow = false
	end
	p.Parent = parent
end

function BiomeKit.block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, opts: PartOpts?): Part
	local p = Instance.new("Part")
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	finish(p, name, cf, size, color, opts, parent)
	return p
end

function BiomeKit.wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, opts: PartOpts?): WedgePart
	local p = Instance.new("WedgePart")
	finish(p, name, cf, size, color, opts, parent)
	return p
end

--- A cylinder standing UP (Roblox's Cylinder runs its axis along local X, so the part
--- is rolled 90 degrees). `h` is the height, `d` the diameter.
function BiomeKit.column(parent: Instance, name: string, at: CFrame, h: number, d: number, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = table.clone(opts or {})
	o.shape = Enum.PartType.Cylinder
	return BiomeKit.block(parent, name, at * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(h, d, d), color, o)
end

--- A flattened ellipsoid lying on the ground (a Sphere SpecialMesh: a round Shape
--- forces a circle, see build/Scenery's oozeDisc). `a`/`b` are the full X/Z extents.
function BiomeKit.disc(
	parent: Instance,
	name: string,
	at: Vector3,
	a: number,
	b: number,
	thick: number,
	yawDeg: number,
	color: Color3,
	opts: PartOpts?
): Part
	local o: PartOpts = table.clone(opts or {})
	o.studs = false
	if o.shadow == nil then
		o.shadow = false
	end
	local p = BiomeKit.block(parent, name, CFrame.new(at) * CFrame.Angles(0, math.rad(yawDeg), 0), Vector3.one, color, o)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, thick, b)
	mesh.Parent = p
	return p
end

--- A flat blob of several overlapping ovals stretched along one axis, so it reads as a
--- puddle or a drift rather than a coin. Each oval on its own height step (`step`) so
--- none of them z-fight. Returns the biggest oval (the one a light goes on).
function BiomeKit.blob(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	y: number,
	size: number,
	thick: number,
	color: Color3,
	rng: Random,
	opts: PartOpts?,
	step: number?
): Part
	local yaw = rng:NextNumber(0, 360)
	local head: Part? = nil
	for i = 1, rng:NextInteger(2, 4) do
		local a = if i == 1 then size else size * rng:NextNumber(0.4, 0.72)
		local b = a / rng:NextNumber(1.2, 2)
		local ox, oz = 0, 0
		if i > 1 then
			local along = math.rad(yaw + (if i % 2 == 0 then 0 else 180) + rng:NextNumber(-30, 30))
			local reach = size * rng:NextNumber(0.2, 0.42)
			ox, oz = math.cos(along) * reach, math.sin(along) * reach
		end
		local p = BiomeKit.disc(parent, name, Vector3.new(x + ox, y + i * (step or 0.003), z + oz), a, b, thick, yaw + rng:NextNumber(-30, 30), color, opts)
		if i == 1 then
			head = p
		end
	end
	return head :: Part
end

--- A studded rock cluster, two or three rotated blocks settling into each other (the
--- same build as build/Scenery's `rock`, sized by the caller).
function BiomeKit.rock(parent: Instance, x: number, z: number, groundY: number, s: number, colors: { Color3 }, rng: Random, name: string?)
	local yaw = rng:NextNumber(0, 360)
	for i = 1, rng:NextInteger(2, 3) do
		local k = 1 - (i - 1) * 0.22
		local size = Vector3.new(s * k * rng:NextNumber(0.8, 1.15), s * k * rng:NextNumber(0.5, 0.78), s * k * rng:NextNumber(0.8, 1.15))
		local ox = if i == 1 then 0 else rng:NextNumber(-0.45, 0.45) * s
		local oz = if i == 1 then 0 else rng:NextNumber(-0.45, 0.45) * s
		local cf = CFrame.new(x + ox, groundY + size.Y * 0.36, z + oz)
			* CFrame.Angles(0, math.rad(yaw + rng:NextNumber(-40, 40)), 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-16, 16)), 0, math.rad(rng:NextNumber(-16, 16)))
		BiomeKit.block(parent, name or "Rock", cf, size, BiomeKit.pick(rng, colors), { studs = true })
	end
end

--- A handful of small stones round a point.
function BiomeKit.grit(parent: Instance, x: number, z: number, groundY: number, colors: { Color3 }, rng: Random, name: string?)
	for _ = 1, rng:NextInteger(3, 6) do
		local s = rng:NextNumber(0.25, 0.75)
		local size = Vector3.new(s * rng:NextNumber(0.8, 1.3), s * rng:NextNumber(0.5, 0.8), s * rng:NextNumber(0.8, 1.3))
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, 1.8)
		local cf = CFrame.new(x + math.cos(t) * d, groundY + size.Y * 0.3, z + math.sin(t) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		BiomeKit.block(parent, name or "Grit", cf, size, BiomeKit.pick(rng, colors))
	end
end

--- A pointed crystal: a square prism with a chisel tip, leaning `tilt`
--- degrees off vertical toward `lean` (degrees of yaw). Built in its own frame
--- standing on `base`, so the tip never floats off the shaft whatever the lean.
function BiomeKit.crystal(
	parent: Instance,
	name: string,
	base: Vector3,
	h: number,
	w: number,
	lean: number,
	tilt: number,
	color: Color3,
	opts: PartOpts?
)
	local frame = CFrame.new(base)
		* CFrame.Angles(0, math.rad(lean), 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
		* CFrame.Angles(0, math.rad(45), 0)
	local shaft = h * 0.72
	local tip = h - shaft
	-- Sunk a little so the lean never lifts the near edge off the ground.
	BiomeKit.block(parent, name, frame * CFrame.new(0, shaft / 2 - 0.25, 0), Vector3.new(w, shaft, w), color, opts)
	-- The tip: two wedges back to back make a chisel ridge. A WedgePart is tall at its
	-- +Z face, so each half sits on the -Z side of the centre with its tall face inward.
	local tipCF = frame * CFrame.new(0, shaft - 0.25 + tip / 2, 0)
	for _, yaw in { 0, 180 } do
		BiomeKit.wedge(parent, name .. "Tip", tipCF * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0, -w / 4), Vector3.new(w, tip, w / 2), color, opts)
	end
end

-- ── Placement ──────────────────────────────────────────────────────────────────

--- Walk a jittered grid over the field, calling `fn(x, z, col, row)` once per cell.
--- The same technique as every scatter in build/Scenery: covers the ground without the
--- clumps and bald patches pure random leaves.
function BiomeKit.grid(f: Field, cell: number, rng: Random, fn: (x: number, z: number, col: number, row: number) -> ())
	local cols = math.max(1, math.floor((f.maxX - f.minX) / cell))
	local rows = math.max(1, math.floor((f.maxZ - f.minZ) / cell))
	local cw, ch = (f.maxX - f.minX) / cols, (f.maxZ - f.minZ) / rows
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local x = f.minX + (col + 0.5 + rng:NextNumber(-0.45, 0.45)) * cw
			local z = f.minZ + (row + 0.5 + rng:NextNumber(-0.45, 0.45)) * ch
			fn(x, z, col, row)
		end
	end
end

--- Deal `count` landmark sites spread over the field: off the lane (by `lanePad` extra),
--- at least `spacing` from each other, and at least `r` from anything in `avoid` (each
--- {x, z, r}: r is that thing's whole clearance, NOT added to `spacing` -- summing the
--- two let a long feature like the rift's polyline block the entire field).
--- Alternates north/south of the lane so both sides of the walk always have one in
--- view. Best-effort: a site that cannot be placed in 60 tries is dropped rather than
--- crammed in.
function BiomeKit.sites(
	f: Field,
	count: number,
	spacing: number,
	rng: Random,
	lanePad: number?,
	avoid: { { number } }?
): { Vector3 }
	local out: { Vector3 } = {}
	local blocked: { { number } } = table.clone(avoid or {})
	local nAvoid = #blocked
	local minZ = BiomeKit.LANE_HALF + (lanePad or 0)
	for i = 1, count do
		local side = if i % 2 == 0 then 1 else -1
		-- Stripe the X range so the sites march down the field instead of bunching.
		local band = (f.maxX - f.minX) / count
		for _ = 1, 60 do
			local x = f.minX + band * (i - 1 + rng:NextNumber(0.1, 0.9))
			local z = side * rng:NextNumber(minZ, math.max(minZ + 1, f.maxZ - 4))
			local ok = true
			for j, b in blocked do
				local dx, dz = x - b[1], z - b[2]
				local need = if j <= nAvoid then b[3] or spacing else spacing
				if dx * dx + dz * dz < need * need then
					ok = false
					break
				end
			end
			if ok then
				table.insert(out, Vector3.new(x, f.groundY, z))
				table.insert(blocked, { x, z, 0 })
				break
			end
		end
	end
	return out
end

-- ── Light and particles ────────────────────────────────────────────────────────

function BiomeKit.glow(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

--- An invisible part to hang an emitter or a light on.
function BiomeKit.anchor(parent: Instance, name: string, at: Vector3, size: Vector3?): Part
	local p = BiomeKit.block(parent, name, CFrame.new(at), size or Vector3.new(1, 0.2, 1), Color3.new(0, 0, 0))
	p.Transparency = 1
	p.CastShadow = false
	return p
end

export type SmokeOpts = {
	texture: string?,
	from: Color3,
	to: Color3,
	size: { number }, -- start, mid, end
	opacity: number, -- peak opacity (0-1)
	lifetime: { number },
	rate: number,
	speed: { number },
	spread: number?,
	accel: Vector3?,
	light: number?, -- LightEmission; 0 = real smoke lit by the sky
	drag: number?,
}

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
BiomeKit.SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

--- A slow emitter on `anchor`, pointing up. The defaults are build/CraterField's vent
--- smoke; every far field tunes its own.
function BiomeKit.smoke(anchor: BasePart, name: string, o: SmokeOpts)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = o.texture or SMOKE_TEXTURE
	e.Color = ColorSequence.new(o.from, o.to)
	e.LightEmission = o.light or 0
	e.LightInfluence = if (o.light or 0) > 0 then 0 else 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, o.size[1]),
		NumberSequenceKeypoint.new(0.3, o.size[2]),
		NumberSequenceKeypoint.new(1, o.size[3]),
	})
	local clear = 1 - o.opacity
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, clear),
		NumberSequenceKeypoint.new(0.55, clear + (1 - clear) * 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(o.lifetime[1], o.lifetime[2])
	e.Rate = o.rate
	e.Speed = NumberRange.new(o.speed[1], o.speed[2])
	local spread = o.spread or 10
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = o.accel or Vector3.new(0.55, 0.1, 0.3)
	e.Drag = o.drag or 0.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-18, 18)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = anchor
end

--- The one WIND every far-field plume leans on, so they drift together (build/CraterField's).
BiomeKit.WIND = Vector3.new(0.55, 0, 0.3)

return BiomeKit
