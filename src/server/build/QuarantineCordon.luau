--!strict
--[[
	QuarantineCordon.luau — a broken hazard-tape cordon strung round one of Stage 4's
	ooze pools: steel posts, two wire strands, yellow-and-black tape sagging between
	them, and a trefoil placard facing out. Somebody fenced the pool off and gave up.

	    called from build/Scenery's buildStageScenery (Stage 4, round the lake, last)

	An ARC, not a ring: a bit over half a circle on the side of the pool away from the
	walk lane, so the route is never fenced. Posts that would land on the lane, off the
	plate or on a tree trunk are skipped, which breaks the arc into runs.

	Each post rolls a state -- standing, leaning, down in the mud or gone -- and the wire
	and tape follow it: taut between two that stand, trailing to the ground off one that
	stands where its neighbour does not. The ends of a run always stand.

	Every part is CanCollide/CanQuery/CanTouch false (dug ground). ITS OWN SEED, never the
	stage rng, so adding it moved no sign, pool or tree.
]]

local K = require(script.Parent.BiomeKit)
local Kit = require(script.Parent.Kit)

local QuarantineCordon = {}

local POST_H = 5
local POST_W = 0.36
local POST_SPACING = 6.5
local WIRE_HEIGHTS = { 1.5, 4.3 }
local TAPE_H = 3.1
local TAPE_SAG = 0.4
local TAPE_W = 0.34

--- Degrees of circle the arc covers, centred on the side away from the lane.
local SWEEP = 210

local C = Kit.C
-- WasteDump's weathered warm grey, matte (a cool grey reads blue off the sky).
local POST = K.hex("7F7B74")
local POST_CAP = K.hex("5E5A54")
local WIRE = K.hex("4E4A44")
local TAPE_YELLOW = K.hex(C.barrelYellow)
local TAPE_BLACK = K.hex(C.hazardBlack)

local NO_SHADOW: K.PartOpts = { shadow = false }

export type Trefoil = (parent: Instance, hub: CFrame, scale: number, color: string) -> ()

--- A square bar between two points.
local function strut(parent: Instance, name: string, a: Vector3, b: Vector3, t: number, color: Color3, opts: K.PartOpts?)
	local d = (b - a).Magnitude
	if d < 0.05 then
		return
	end
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	K.block(parent, name, CFrame.lookAt((a + b) / 2, b, up), Vector3.new(t, t, d), color, opts)
end

--- One length of tape from `a` to `b`, with black bands across it.
local function tape(parent: Instance, a: Vector3, b: Vector3)
	local d = (b - a).Magnitude
	if d < 0.1 then
		return
	end
	local frame = CFrame.lookAt((a + b) / 2, b, Vector3.yAxis)
	K.block(parent, "Tape", frame, Vector3.new(0.05, TAPE_W, d), TAPE_YELLOW, NO_SHADOW)
	local bands = math.max(1, math.floor(d / 1.6))
	for i = 1, bands do
		local along = -d / 2 + (i - 0.5) * d / bands
		K.block(parent, "TapeBand", frame * CFrame.new(0, 0, along), Vector3.new(0.07, TAPE_W + 0.02, 0.36), TAPE_BLACK, NO_SHADOW)
	end
end

--- A trefoil placard wired to a post, facing `face` (flat unit vector).
local function placard(parent: Instance, trefoil: Trefoil, at: Vector3, face: Vector3, rng: Random)
	local board = CFrame.fromMatrix(at + face * (POST_W / 2 + 0.07), face, Vector3.yAxis)
		* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, 0)
	K.block(parent, "Placard", board, Vector3.new(0.12, 2.2, 2.6), TAPE_YELLOW, nil)
	K.block(parent, "PlacardBand", board * CFrame.new(0.07, 0.82, 0), Vector3.new(0.05, 0.5, 2.6), TAPE_BLACK, nil)
	trefoil(parent, board * CFrame.new(0.08, -0.22, 0), 0.62, C.hazardBlack)
end

type Post = { foot: Vector3, top: Vector3, up: boolean }

--- One broken run along `path` (post positions on the ground).
local function run(parent: Instance, path: { Vector3 }, groundY: number, rng: Random, trefoil: Trefoil, face: Vector3?)
	local model = Instance.new("Model")
	model.Name = "Cordon"
	local posts: { Post } = {}
	for i, at in path do
		local foot = Vector3.new(at.X, groundY, at.Z)
		local nxt, prv = path[math.min(#path, i + 1)], path[math.max(1, i - 1)]
		local dir = Vector3.new(nxt.X - prv.X, 0, nxt.Z - prv.Z)
		dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.xAxis
		local across = Vector3.new(-dir.Z, 0, dir.X)
		local roll = if i == 1 or i == #path then 0 else rng:NextNumber()
		if roll < 0.84 then
			local lean = if roll < 0.64 then rng:NextNumber(-3, 3) else (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(12, 26)
			local top = foot + across * math.sin(math.rad(lean)) * POST_H + Vector3.new(0, math.cos(math.rad(lean)) * POST_H, 0)
			posts[i] = { foot = foot, top = top, up = true }
		else
			if roll < 0.94 then
				-- Down: lying in the mud off its hole, a stub left standing.
				local fall = CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0).LookVector
				local a = foot + Vector3.new(0, POST_W / 2, 0) + fall * 0.4
				strut(model, "PostDown", a, a + fall * (POST_H - 0.6), POST_W, POST, nil)
				K.block(model, "PostStub", CFrame.new(foot + Vector3.new(0, 0.3, 0)), Vector3.new(POST_W, 0.6, POST_W), POST, nil)
			end
			posts[i] = { foot = foot, top = foot, up = false }
		end
	end

	local function at(post: Post, h: number): Vector3
		return post.foot:Lerp(post.top, h / POST_H)
	end

	for i, post in posts do
		if post.up then
			strut(model, "Post", post.foot - Vector3.new(0, 0.2, 0), post.top, POST_W, POST, nil)
			K.block(model, "PostCap", CFrame.lookAt(post.top, post.top + (post.top - post.foot).Unit) * CFrame.new(0, 0, -0.08), Vector3.new(POST_W + 0.1, POST_W + 0.1, 0.16), POST_CAP, nil)
		end
		local nxt = posts[i + 1]
		if not nxt then
			continue
		end
		if post.up and nxt.up then
			for _, h in WIRE_HEIGHTS do
				strut(model, "Wire", at(post, h), at(nxt, h), 0.07, WIRE, NO_SHADOW)
			end
			local a, b = at(post, TAPE_H), at(nxt, TAPE_H)
			local mid = (a + b) / 2 - Vector3.new(0, TAPE_SAG, 0)
			tape(model, a, mid)
			tape(model, mid, b)
		elseif post.up or nxt.up then
			-- Snapped: the tape and the top wire hang off the standing post to the mud.
			local from = if post.up then post else nxt
			local to = if post.up then nxt else post
			local ground = from.foot:Lerp(to.foot, rng:NextNumber(0.3, 0.55)) + Vector3.new(0, 0.05, 0)
			tape(model, at(from, TAPE_H), ground)
			tape(model, ground, ground + (to.foot - from.foot).Unit * rng:NextNumber(0.8, 2) + Vector3.new(0, 0.02, 0))
			strut(model, "Wire", at(from, WIRE_HEIGHTS[2]), ground + Vector3.new(0.3, 0, 0.3), 0.07, WIRE, NO_SHADOW)
		end
	end

	if face then
		-- On a standing post near the middle of the run.
		local mid = math.ceil(#posts / 2)
		for off = 0, #posts do
			local post = posts[mid + (if off % 2 == 0 then off // 2 else -(off + 1) // 2)]
			if post and post.up then
				placard(model, trefoil, at(post, 2.4), face, rng)
				break
			end
		end
	end

	model.Parent = parent
end

--- A cordon round the pool centred on world (`cx`, `cz`), `radius` out. `minX..maxZ` is
--- the plate less its margin; `laneHalf` the walk lane's half-width; `avoid` world
--- points (tree trunks) no post may stand within 3 studs of.
function QuarantineCordon.build(
	parent: Instance,
	cx: number,
	cz: number,
	radius: number,
	groundY: number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	laneHalf: number,
	avoid: { Vector3 },
	seed: number,
	trefoil: Trefoil
)
	local rng = Random.new(seed)
	local folder = Instance.new("Folder")
	folder.Name = "Cordon"

	-- Centred on the side away from the lane (z = 0), with a little jitter.
	local away = if cz >= 0 then 90 else -90
	local a0 = away - SWEEP / 2 + rng:NextNumber(-20, 20)
	local steps = math.max(2, math.floor(math.rad(SWEEP) * radius / POST_SPACING))

	local path: { Vector3 } = {}
	local function flush()
		if #path >= 3 then
			local mid = path[math.ceil(#path / 2)]
			local face = Vector3.new(mid.X - cx, 0, mid.Z - cz)
			run(folder, path, groundY, rng, trefoil, if face.Magnitude > 0 then face.Unit else nil)
		end
		path = {}
	end
	for s = 0, steps do
		local ang = math.rad(a0 + SWEEP * s / steps)
		local x, z = cx + math.cos(ang) * radius, cz + math.sin(ang) * radius
		local ok = x > bounds.minX and x < bounds.maxX and z > bounds.minZ and z < bounds.maxZ and math.abs(z) > laneHalf + 1
		if ok then
			for _, p in avoid do
				if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < 9 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(path, Vector3.new(x, groundY, z))
		else
			flush()
		end
	end
	flush()

	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	folder.Parent = parent
end

return QuarantineCordon
