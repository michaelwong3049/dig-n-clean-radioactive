--!strict
--[[
	WasteDump.luau — Stage 3 as an abandoned radioactive waste dump: somebody trucked
	drums out here for years, buried what they could and left the rest.

	    called from build/Scenery's buildStageScenery (Stage 3, after the drums)

	WHAT IS OUT HERE, landmarks first:

	  * THE CRANE — one derelict crawler crane, boom still raised, a drum still hanging
	    off the hook where the job stopped. The tallest thing on the field and the one to
	    steer by from the entrance.
	  * THE DUMP TRUCK — tipper bed jacked up, tailgate hanging open, its last load of
	    dirt and drums spilled out behind it.
	  * DRUM YARDS — drums stood on wooden pallets, two by two, the odd one laid across
	    the top, behind a run of chain-link that has mostly given up. Every yard has a
	    trefoil board on its fence facing the walk.
	  * BURIAL TRENCHES — long dug strips between spoil heaps, drum tops poking out of the
	    dirt where they were never covered, a shovel left in the heap.
	  * THE GROUND — tyre ruts running from the yards and the truck out to the walk,
	    crushed drums, loose lids, old tyres and dark sludge stains. NONE OF IT GLOWS
	    (the user's call for this pass): the first Neon on the chain stays Stage 4's ooze,
	    so the sludge is a dark stain and not a pool.

	The field's own drums (build/Scenery's scatterBarrels) and its bones stay exactly as
	they were; this module reads where they landed (`parent.Barrels`, `parent.Bones`)
	and keeps its set pieces off them, rather than moving a single one.

	THE PARTS ARE build/BiomeKit's, and so are its standing rules: every part
	CanCollide/CanQuery/CanTouch false, so a player walks through all of it and
	FieldController's range-ring raycast and DigService's burial pass straight to the
	plate (this IS dug ground, unlike the far biomes); anything that stands up keeps off
	the walk lane down z = 0; studs on wood, soil and concrete, smooth metal.

	THE DRUMS ARE build/Scenery's `radBarrel`, handed in (`Drums`), not a second drum —
	a yard of drums that did not match the ones already dumped on the field would read
	as two props. Same for the trefoil on the boards (`flatTrefoil`).

	FLAT THINGS STAY UNDER A DETECTOR SPOT'S CRACKS (0.15 over the cap, see
	build/FieldLitter's header): ruts top out 0.08, trench floors 0.09, sludge 0.12.

	ITS OWN SEED, never the stage rng, so this cannot move a bone or a drum.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)
local Kit = require(script.Parent.Kit)

local WasteDump = {}

local SEED = 8300

--- Scenery's drum, handed in so every drum on this field is the same drum. `build`
--- stands one on `base` (local y = 0, axis up local Y); `h`/`r`/`chime` are its
--- dimensions, which a lying or stacked drum needs to rest correctly.
export type Drums = {
	build: (parent: Instance, base: CFrame, rng: Random) -> (),
	trefoil: (parent: Instance, hub: CFrame, scale: number, color: string) -> (),
	h: number,
	r: number,
	chime: number,
}

-- 3 / 3 -> 0 / 0 in the minimal-decor pass (2026-10-03): the dump is the crane and
-- the truck now, on request. yard()/trench() stay for a revival.
local YARDS = 0
local TRENCHES = 0
--- Share of a pallet's four slots that hold a drum, and the chance a pallet row gets a
--- drum laid across its tops.
local SLOT_FILLED = 0.8
local TOPPER = 0.45

local FENCE_H = 6
local FENCE_SECTION = 6
--- Diamond pitch of the chain-link. Wide on purpose: it has to read as mesh from across
--- the field, and every diagonal is a part.
local MESH_PITCH = 1.5

--- Ground scatter: one roll per CELL-stud cell, skipped wherever a set piece stands.
--- Roughly one live cell in five carries something. Lower (0.13) shot live as about
--- sixteen pieces over the whole field once the set pieces' own ground was skipped,
--- which read as swept rather than dumped on.
local CELL = 16
-- All x0.3 in the minimal-decor pass (2026-10-03).
local CRUSHED_CHANCE = 0.006
local LID_CHANCE = 0.0045
local TYRE_CHANCE = 0.003
local SLUDGE_CHANCE = 0.0036

--- Tyre-track gauge (centre to centre) and one rut's width.
local RUT_GAUGE = 4
local RUT_W = 0.9

-- ── Colour ─────────────────────────────────────────────────────────────────────

local C = Kit.C
local DRUM_YELLOW = C.barrelYellow
local WOOD = { K.hex("7A6446"), K.hex("6A563C"), K.hex("85704F") }
local STEEL = K.hex("5A6270")
local STEEL_DARK = K.hex("3A3F47")
local RUBBER = K.hex("22262C")
local RUBBER_WORN = K.hex("33373D")
local RUST = { K.hex("7A4430"), K.hex("5E3526") }
-- Faded plant orange: far enough off the drums' yellow that the crane never reads as
-- a giant drum, and off the khaki ground that it holds its silhouette at fog range.
local CRANE_PAINT = K.hex("B8622E")
local CRANE_FADED = K.hex("9A5634")
-- Dull teal for the truck, the one colour nothing else on this field is.
local TRUCK_PAINT = K.hex("4F6B6E")
local TRUCK_DARK = K.hex("3C5255")
-- Dark and non-reflective: reflectance on an upward-ish pane mirrors the sky pale
-- (the lesson Glass Barrens shot live).
local WINDOW = K.hex("252C31")
-- Weathered WARM grey, and matte. Shot live, a galvanised cool grey (9BA3AA) read
-- bright blue from across the field whether in Metal or SmoothPlastic: wires this
-- thin are nearly all edge, and their edges pick up the sky.
local FENCE_POST = K.hex("7F7B74")
local FENCE_WIRE = K.hex("7A746A")
local SLUDGE = K.hex("39372A")

local ASH = K.hex("4A3F32")

type Palette = { spoil: { Color3 }, trench: Color3, rut: Color3 }

--- Soil colours off the stage's own floor, pushed DARKER: on light khaki a darker
--- smear reads as dirt at once, a lighter one reads as spilled paint (build/FieldLitter).
local function paletteFor(stageId: number): Palette
	local base = K.hex(Stages.get(stageId).color)
	return {
		spoil = { base:Lerp(ASH, 0.22), base:Lerp(ASH, 0.36), K.shade(base, -0.12) },
		trench = base:Lerp(ASH, 0.68),
		rut = base:Lerp(ASH, 0.34),
	}
end

local METAL: K.PartOpts = { material = Enum.Material.Metal }
local STUDS: K.PartOpts = { studs = true }

local function rustBlend(rng: Random, max: number): Color3
	return K.hex(Kit.blendHex(DRUM_YELLOW, C.barrelRust, rng:NextNumber(0, max)))
end

-- ── Small helpers ──────────────────────────────────────────────────────────────

--- A square bar between two points.
local function strut(parent: Instance, name: string, a: Vector3, b: Vector3, t: number, color: Color3, opts: K.PartOpts?): Part?
	local d = (b - a).Magnitude
	if d < 0.05 then
		return nil
	end
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return K.block(parent, name, CFrame.lookAt((a + b) / 2, b, up), Vector3.new(t, t, d), color, opts)
end

--- A round bar between two points (a Cylinder's axis is its local X, so the lookAt
--- frame is turned a quarter about Y to lay X along the run).
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, opts: K.PartOpts?)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	local o: K.PartOpts = table.clone(opts or {})
	o.shape = Enum.PartType.Cylinder
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	K.block(parent, name, CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(len, d, d), color, o)
end

--- A wheel on an axle along the frame's X.
local function wheel(parent: Instance, at: CFrame, d: number, w: number)
	K.block(parent, "Tyre", at, Vector3.new(w, d, d), RUBBER, { shape = Enum.PartType.Cylinder })
	K.block(parent, "Hub", at, Vector3.new(w + 0.06, d * 0.45, d * 0.45), STEEL, { shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
end

type Taken = { { number } }

local function clearOf(taken: Taken, x: number, z: number, r: number): boolean
	for _, t in taken do
		local need = r + (t[3] or 0)
		local dx, dz = x - t[1], z - t[2]
		if dx * dx + dz * dz < need * need then
			return false
		end
	end
	return true
end

-- ── Drums ──────────────────────────────────────────────────────────────────────

local function standing(parent: Instance, drums: Drums, at: Vector3, rng: Random, lean: number?)
	local tilt = lean or rng:NextNumber(-2.5, 2.5)
	drums.build(
		parent,
		CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(math.rad(tilt), 0, 0),
		rng
	)
end

--- A drum on its side, its MIDDLE at `mid` (x/z), resting on `restY`, its axis along
--- `yaw`. Rests on its chimes, not its shell, the way scatterBarrels' fallen ones do.
local function lying(parent: Instance, drums: Drums, mid: Vector3, restY: number, yaw: number, rng: Random)
	local base = CFrame.new(mid.X, restY + drums.r + drums.chime, mid.Z)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(90), 0, 0)
		* CFrame.new(0, -drums.h / 2, 0)
	drums.build(parent, base, rng)
end

--- The top of a drum sticking out of the dirt: shell, chime, lid and bung, the rest
--- below the plate where nobody sees it. Four parts where a whole drum is forty.
local function drumTop(parent: Instance, drums: Drums, at: CFrame, rng: Random)
	local body = rustBlend(rng, 0.55)
	local stick = rng:NextNumber(0.5, 1.1)
	K.column(parent, "BuriedDrum", at * CFrame.new(0, stick / 2 - 0.3, 0), stick + 0.6, drums.r * 2, body, METAL)
	K.column(parent, "Chime", at * CFrame.new(0, stick - 0.14, 0), 0.3, (drums.r + drums.chime) * 2, K.shade(body, 0.1), METAL)
	K.column(parent, "Lid", at * CFrame.new(0, stick + 0.01, 0), 0.1, drums.r * 2 - 0.12, K.shade(body, 0.1), METAL)
	K.column(parent, "Bung", at * CFrame.new(drums.r * 0.46, stick + 0.1, drums.r * 0.24), 0.16, 0.4, STEEL_DARK, METAL)
end

--- A drum run over and flattened: a block, not a cylinder (a round Shape cannot be
--- squashed into an oval), with its chimes and a hazard band still showing.
local function crushedDrum(parent: Instance, x: number, z: number, groundY: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "CrushedDrum"
	local h = rng:NextNumber(0.7, 1.1)
	local cf = CFrame.new(x, groundY + h / 2 - 0.05, z)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6)))
	local body = rustBlend(rng, 0.6)
	K.block(model, "Crushed", cf, Vector3.new(4, h, 2.9), body, METAL)
	for _, sx in { -1, 1 } do
		K.block(model, "Chime", cf * CFrame.new(sx * 1.85, 0, 0), Vector3.new(0.3, h + 0.12, 3.05), K.shade(body, 0.1), METAL)
		K.block(model, "Band", cf * CFrame.new(sx * 1.1, 0, 0), Vector3.new(0.6, h + 0.04, 2.94), K.hex(C.hazardBlack), METAL)
	end
	model.Parent = parent
end

local function lid(parent: Instance, x: number, z: number, groundY: number, rng: Random)
	local cf = CFrame.new(x, groundY + 0.1, z) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6)))
	K.column(parent, "DrumLid", cf, 0.1, 2.5, rustBlend(rng, 0.7), METAL)
end

--- A stack of one to `max` old tyres, lying flat.
local function tyres(parent: Instance, x: number, z: number, groundY: number, max: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Tyres"
	local y = groundY
	for _ = 1, rng:NextInteger(1, max) do
		local cf = CFrame.new(x + rng:NextNumber(-0.3, 0.3), y + 0.45, z + rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, math.rad(rng:NextNumber(-4, 4)))
		K.column(model, "Tyre", cf, 0.9, 3, RUBBER, nil)
		-- The hole: a darker disc just proud of the top face.
		K.column(model, "TyreHole", cf * CFrame.new(0, 0.02, 0), 0.9, 1.5, RUBBER_WORN, nil)
		y += 0.9
	end
	model.Parent = parent
end

local function sludge(parent: Instance, x: number, z: number, groundY: number, size: number, rng: Random)
	K.blob(parent, "Sludge", x, z, groundY + 0.1, size, 0.03, SLUDGE, rng, { transparency = 0.1 }, 0.002)
end

-- ── Chain-link ─────────────────────────────────────────────────────────────────

--- One fence section `s` long, built in `F` (local X along the run, Y up, standing on
--- y = 0): its post at x = 0, a top rail, and the mesh as two families of diagonals
--- clipped to the panel.
local function section(parent: Instance, F: CFrame, s: number, post: boolean)
	if post then
		K.column(parent, "FencePost", F * CFrame.new(0, FENCE_H / 2, 0), FENCE_H, 0.32, FENCE_POST, nil)
	end
	K.block(parent, "FenceRail", F * CFrame.new(s / 2, FENCE_H - 0.15, 0), Vector3.new(s, 0.18, 0.18), FENCE_POST, nil)
	local y0, y1 = 0.35, FENCE_H - 0.25
	local function wire(ax: number, ay: number, bx: number, by: number)
		strut(parent, "FenceWire", (F * CFrame.new(ax, ay, 0)).Position, (F * CFrame.new(bx, by, 0)).Position, 0.06, FENCE_WIRE, nil)
	end
	-- Rising diagonals: y - x = c.
	local c = y0 - s + MESH_PITCH / 2
	while c < y1 do
		local xa, xb = math.max(0, y0 - c), math.min(s, y1 - c)
		if xb - xa > 0.3 then
			wire(xa, xa + c, xb, xb + c)
		end
		c += MESH_PITCH
	end
	-- Falling diagonals: y + x = c.
	c = y0 + MESH_PITCH / 2
	while c < y1 + s do
		local xa, xb = math.max(0, c - y1), math.min(s, c - y0)
		if xb - xa > 0.3 then
			wire(xa, c - xa, xb, c - xb)
		end
		c += MESH_PITCH
	end
end

--- A trefoil board hung on a post, facing `face` (a flat unit vector).
local function sign(parent: Instance, drums: Drums, at: Vector3, face: Vector3, rng: Random)
	local board = CFrame.fromMatrix(at + face * 0.26, face, Vector3.yAxis) * CFrame.Angles(math.rad(rng:NextNumber(-7, 7)), 0, 0)
	K.block(parent, "SignBoard", board, Vector3.new(0.12, 2.2, 2.6), K.hex(DRUM_YELLOW), nil)
	K.block(parent, "SignBand", board * CFrame.new(0.07, 0.82, 0), Vector3.new(0.05, 0.5, 2.6), K.hex(C.hazardBlack), nil)
	drums.trefoil(parent, board * CFrame.new(0.08, -0.22, 0), 0.62, C.hazardBlack)
end

--- A broken run of chain-link from `a` to `b`. Each section rolls its own state:
--- standing, leaning off plumb, flattened, or gone to a snapped stub. `signFace`, if
--- given, hangs a trefoil board on the middle post facing that way.
local function fenceRun(parent: Instance, a: Vector3, b: Vector3, rng: Random, drums: Drums, signFace: Vector3?)
	local model = Instance.new("Model")
	model.Name = "ChainLink"
	local run = b - a
	local len = run.Magnitude
	local dir = run.Unit
	local n = math.max(1, math.round(len / FENCE_SECTION))
	local s = len / n
	local signAt = if signFace then math.ceil(n / 2) else -1
	for i = 1, n do
		local F = CFrame.fromMatrix(a + dir * (s * (i - 1)), dir, Vector3.yAxis)
		local roll = rng:NextNumber()
		-- The signed section always stands: a board on a flattened fence is lost.
		if i == signAt then
			roll = 0
		end
		if roll < 0.58 then
			section(model, F * CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, 0), s, true)
			if i == signAt and signFace then
				sign(model, drums, (F * CFrame.new(0, 3.4, 0)).Position, signFace, rng)
			end
		elseif roll < 0.8 then
			local lean = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(12, 24)
			section(model, F * CFrame.Angles(math.rad(lean), 0, 0), s, true)
		elseif roll < 0.9 then
			-- Flattened: the panel lies on the ground beside its line, the post snapped.
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			section(model, F * CFrame.new(0, 0.12, 0) * CFrame.Angles(math.rad(side * 88), 0, 0), s, false)
			K.column(model, "SnappedPost", F * CFrame.new(0, 0.7, 0) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, 0), 1.4, 0.32, FENCE_POST, nil)
		else
			K.column(model, "SnappedPost", F * CFrame.new(0, 0.9, 0), 1.8, 0.32, FENCE_POST, nil)
		end
	end
	-- The closing post, unless the last section went down with it.
	K.column(model, "FencePost", CFrame.new(b) * CFrame.new(0, FENCE_H / 2, 0), FENCE_H, 0.32, FENCE_POST, nil)
	model.Parent = parent
end

-- ── Drum yard ──────────────────────────────────────────────────────────────────

--- A 6 x 6 pallet on `frame` (standing on its y = 0). Returns the deck's top frame.
local function pallet(parent: Instance, frame: CFrame, rng: Random): CFrame
	local wood = K.pick(rng, WOOD)
	for _, x in { -2.5, 0, 2.5 } do
		K.block(parent, "PalletRunner", frame * CFrame.new(x, 0.22, 0), Vector3.new(0.9, 0.44, 6), K.shade(wood, -0.12), STUDS)
	end
	for i = 0, 4 do
		-- The odd slat has gone, which is most of what reads as a pallet left out.
		if i == 2 or rng:NextNumber() > 0.12 then
			K.block(parent, "PalletSlat", frame * CFrame.new(0, 0.53, -2.5 + i * 1.25), Vector3.new(6, 0.18, 0.95), wood, STUDS)
		end
	end
	return frame * CFrame.new(0, 0.62, 0)
end

local function yard(parent: Instance, at: Vector3, rng: Random, drums: Drums, taken: Taken)
	local model = Instance.new("Model")
	model.Name = "DrumYard"
	local out = if at.Z > 0 then 1 else -1
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(-18, 18)), 0)
	local pallets = rng:NextInteger(2, 3)
	local pitch = 7.4
	local span = (pallets - 1) * pitch
	local slot = drums.r + drums.chime + 0.03

	for p = 1, pallets do
		local pf = frame * CFrame.new(-span / 2 + (p - 1) * pitch, 0, out * rng:NextNumber(-0.6, 0.6)) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0)
		local top = pallet(model, pf, rng)
		for _, sz in { -1, 1 } do
			local row = 0
			for _, sx in { -1, 1 } do
				if rng:NextNumber() < SLOT_FILLED then
					row += 1
					standing(model, drums, (top * CFrame.new(sx * slot, 0, sz * slot)).Position, rng)
				end
			end
			-- One laid across a full row's tops.
			if row == 2 and rng:NextNumber() < TOPPER then
				local mid = (top * CFrame.new(rng:NextNumber(-0.3, 0.3), 0, sz * slot)).Position
				-- `lying` lays the axis along (sin yaw, 0, cos yaw); this is the pallet's X.
				local yaw = math.deg(math.atan2(top.XVector.X, top.XVector.Z)) + rng:NextNumber(-8, 8)
				lying(model, drums, mid, top.Y + drums.h + 0.12, yaw, rng)
			end
		end
	end

	-- One that came off: over on its side on the lane side of the pallets, leaking into
	-- a dark stain.
	local fall = (frame * CFrame.new(rng:NextNumber(-span / 2, span / 2), 0, -out * rng:NextNumber(5.5, 7))).Position
	lying(model, drums, fall, at.Y, rng:NextNumber(0, 360), rng)
	sludge(model, fall.X + rng:NextNumber(-1, 1), fall.Z + rng:NextNumber(-1, 1), at.Y, rng:NextNumber(4, 6.5), rng)

	if rng:NextNumber() < 0.6 then
		local tx = (frame * CFrame.new((span / 2 + 5.5) * (if rng:NextNumber() < 0.5 then -1 else 1), 0, out * 1.5)).Position
		tyres(model, tx.X, tx.Z, at.Y, 4, rng)
	end

	-- The fence: along the back (the side away from the walk) and short returns at
	-- each end, open toward the lane. The board faces the walk.
	local hx = span / 2 + 6
	local back = out * 5.8
	local corners = {
		(frame * CFrame.new(-hx, 0, back)).Position,
		(frame * CFrame.new(hx, 0, back)).Position,
	}
	local inward = (frame.Rotation * Vector3.new(0, 0, -out)).Unit
	fenceRun(model, corners[1], corners[2], rng, drums, inward)
	for i, sx in { -1, 1 } do
		if rng:NextNumber() < 0.75 then
			local reach = rng:NextNumber(4, 9)
			fenceRun(model, corners[i], (frame * CFrame.new(sx * hx, 0, back - out * reach)).Position, rng, drums, nil)
		end
	end

	model.Parent = parent
	table.insert(taken, { at.X, at.Z, hx + 2 })
end

-- ── Burial trench ──────────────────────────────────────────────────────────────

local function trench(parent: Instance, at: Vector3, rng: Random, drums: Drums, palette: Palette, taken: Taken)
	local model = Instance.new("Model")
	model.Name = "BurialTrench"
	local L = rng:NextNumber(16, 22)
	local W = rng:NextNumber(3.4, 4.2)
	local T = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0)

	-- The dug floor: 0.09 thick from the cap, so a dirt drift from build/FieldLitter
	-- (tops out 0.05) under it is hidden rather than z-fighting.
	K.block(model, "TrenchFloor", T * CFrame.new(0, 0.045, 0), Vector3.new(L, 0.09, W), palette.trench, { shadow = false })

	-- Spoil heaped along both sides, higher on one.
	local tall = if rng:NextNumber() < 0.5 then -1 else 1
	for _, side in { -1, 1 } do
		local x = -L / 2 + rng:NextNumber(0, 1)
		while x < L / 2 do
			local k = if side == tall then 1 else 0.7
			local size = Vector3.new(rng:NextNumber(2.4, 3.4), rng:NextNumber(0.8, 1.4) * k, rng:NextNumber(1.8, 2.5) * k)
			local cf = T
				* CFrame.new(x, size.Y * 0.3, side * (W / 2 + size.Z * 0.45))
				* CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0)
				* CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-10, 10)))
			K.block(model, "Spoil", cf, size, K.pick(rng, palette.spoil), STUDS)
			x += rng:NextNumber(2.2, 3)
		end
	end

	-- What went in and never got covered: drum tops, and now and then one tipped in on
	-- its side and half-sunk.
	local x = -L / 2 + 2
	while x < L / 2 - 1.5 do
		local roll = rng:NextNumber()
		local z = rng:NextNumber(-0.35, 0.35) * W
		if roll < 0.55 then
			drumTop(model, drums, T * CFrame.new(x, 0.09, z) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-12, 12))), rng)
		elseif roll < 0.72 then
			local mid = (T * CFrame.new(x, 0, z)).Position
			lying(model, drums, mid, at.Y - drums.r * 0.95, rng:NextNumber(0, 360), rng)
		end
		x += rng:NextNumber(3.2, 4.2)
	end
	local pool = (T * CFrame.new(rng:NextNumber(-L / 3, L / 3), 0, 0)).Position
	sludge(model, pool.X, pool.Z, at.Y + 0.02, W * 0.9, rng)

	-- The shovel, stuck in the spoil at one end.
	local sx = (if rng:NextNumber() < 0.5 then -1 else 1) * (L / 2 + 0.6)
	local foot = (T * CFrame.new(sx, 0, tall * (W / 2 + 0.8))).Position
	local lean = T.Rotation * Vector3.new(if sx > 0 then 0.35 else -0.35, 1, tall * 0.2)
	local grip = foot + lean.Unit * 4
	rod(model, "ShovelHandle", foot + Vector3.new(0, 0.6, 0), grip, 0.22, WOOD[1], nil)
	K.block(model, "ShovelBlade", CFrame.lookAt(foot + Vector3.new(0, 0.3, 0), grip) * CFrame.Angles(math.rad(90), 0, 0), Vector3.new(1, 1.3, 0.1), STEEL, METAL)

	model.Parent = parent
	table.insert(taken, { at.X, at.Z, L / 2 + 3 })
end

-- ── The truck ──────────────────────────────────────────────────────────────────

--- A tipper truck, forward = local -Z, bed jacked up about its rear hinge and its load
--- spilled out behind it. Returns the frame, for the ruts.
local function truck(parent: Instance, at: Vector3, yaw: number, rng: Random, drums: Drums, palette: Palette): CFrame
	local model = Instance.new("Model")
	model.Name = "DumpTruck"
	-- A few degrees down on one corner: a flat tyre.
	local Tk = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(rng:NextNumber(-1.5, 1.5)), 0, math.rad(rng:NextNumber(-3, 3)))

	local wd = 2.8
	for _, z in { -5, 3.2, 5.9 } do
		for _, sx in { -1, 1 } do
			wheel(model, Tk * CFrame.new(sx * 2.35, wd / 2, z), wd, 0.95)
		end
	end
	for _, sx in { -1, 1 } do
		K.block(model, "ChassisRail", Tk * CFrame.new(sx * 1.6, 1.9, 0.5), Vector3.new(0.5, 0.6, 14), STEEL_DARK, METAL)
	end
	K.block(model, "Bumper", Tk * CFrame.new(0, 1.4, -7.05), Vector3.new(5.8, 0.7, 0.5), STEEL_DARK, METAL)

	-- The cab, cab-over, rust coming through on the doors.
	local cab = Tk * CFrame.new(0, 4.1, -5)
	K.block(model, "Cab", cab, Vector3.new(5.4, 3.8, 3.8), TRUCK_PAINT, nil)
	K.block(model, "CabRoof", cab * CFrame.new(0, 1.95, 0.1), Vector3.new(5.2, 0.12, 3.5), TRUCK_DARK, nil)
	K.block(model, "Windscreen", cab * CFrame.new(0, 0.8, -1.92), Vector3.new(4.4, 1.5, 0.08), WINDOW, nil)
	K.block(model, "Grille", cab * CFrame.new(0, -1.2, -1.93), Vector3.new(3.2, 1.1, 0.08), STEEL_DARK, METAL)
	for _, sx in { -1, 1 } do
		K.block(model, "SideWindow", cab * CFrame.new(sx * 2.73, 0.8, -0.4), Vector3.new(0.08, 1.3, 1.8), WINDOW, nil)
		K.block(model, "Headlight", cab * CFrame.new(sx * 2.1, -1.2, -1.94), Vector3.new(0.7, 0.5, 0.08), K.hex("B8BCB4"), nil)
		K.block(model, "DoorRust", cab * CFrame.new(sx * 2.72, -0.9, 0.5), Vector3.new(0.06, rng:NextNumber(0.6, 1.2), rng:NextNumber(0.8, 1.6)), K.pick(rng, RUST), nil)
	end

	-- The bed, tipped about its rear hinge (the -Z end rises under a positive X turn).
	local tip = rng:NextNumber(28, 40)
	local Bf = Tk * CFrame.new(0, 2.3, 7.4) * CFrame.Angles(math.rad(tip), 0, 0)
	local bedLen = 9.6
	K.block(model, "BedFloor", Bf * CFrame.new(0, 0.15, -bedLen / 2), Vector3.new(5.6, 0.3, bedLen), TRUCK_DARK, nil)
	for _, sx in { -1, 1 } do
		K.block(model, "BedSide", Bf * CFrame.new(sx * 2.65, 1.5, -bedLen / 2), Vector3.new(0.3, 2.4, bedLen), TRUCK_PAINT, nil)
		K.block(model, "BedRust", Bf * CFrame.new(sx * 2.82, rng:NextNumber(0.9, 1.9), -rng:NextNumber(2, 7)), Vector3.new(0.06, rng:NextNumber(0.7, 1.2), rng:NextNumber(1.2, 2.4)), K.pick(rng, RUST), nil)
	end
	K.block(model, "Headboard", Bf * CFrame.new(0, 1.9, -bedLen + 0.15), Vector3.new(5.6, 3.2, 0.3), TRUCK_PAINT, nil)
	-- The tailgate, hinged along its top edge and hanging plumb whatever the bed does.
	local hinge = (Bf * CFrame.new(0, 2.7, 0.15)).Position
	local gateRot = Tk.Rotation * CFrame.Angles(math.rad(rng:NextNumber(-12, -4)), 0, 0)
	K.block(model, "Tailgate", CFrame.new(hinge) * gateRot * CFrame.new(0, -1.2, 0), Vector3.new(5.6, 2.4, 0.25), TRUCK_PAINT, nil)
	-- The ram.
	local ramFoot = (Tk * CFrame.new(0, 2.1, -2.4)).Position
	local ramHead = (Bf * CFrame.new(0, -0.05, -6.6)).Position
	rod(model, "RamBarrel", ramFoot, ramFoot:Lerp(ramHead, 0.55), 0.75, STEEL_DARK, METAL)
	rod(model, "RamRod", ramFoot:Lerp(ramHead, 0.5), ramHead, 0.42, K.hex("A8ADB3"), METAL)

	-- The load: a heap of dirt out of the back, three drums rolled clear of it, the
	-- ground stained under them.
	local groundY = at.Y
	for _ = 1, rng:NextInteger(5, 7) do
		local p = Tk * CFrame.new(rng:NextNumber(-2.6, 2.6), 0, 8.4 + rng:NextNumber(0, 3.2))
		K.rock(model, p.X, p.Z, groundY, rng:NextNumber(1.4, 2.4), palette.spoil, rng, "Load")
	end
	for i = 1, 3 do
		local p = Tk * CFrame.new(rng:NextNumber(-3.5, 3.5) + (i - 2) * 2.2, 0, 11.5 + rng:NextNumber(0, 3.5))
		lying(model, drums, p.Position, groundY, rng:NextNumber(0, 360), rng)
	end
	local stain = Tk * CFrame.new(0, 0, 12)
	sludge(model, stain.X, stain.Z, groundY, rng:NextNumber(6, 8), rng)

	model.Parent = parent
	return Tk
end

-- ── The crane ──────────────────────────────────────────────────────────────────

--- A crawler crane, boom raised toward local -Z, with a drum still slung off its hook.
local function crane(parent: Instance, at: Vector3, yaw: number, rng: Random, drums: Drums)
	local model = Instance.new("Model")
	model.Name = "Crane"
	local Cf = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)
	local groundY = at.Y

	-- Crawler tracks.
	for _, sx in { -1, 1 } do
		K.block(model, "Track", Cf * CFrame.new(sx * 3.1, 0.9, 0), Vector3.new(2.2, 1.8, 10), STEEL_DARK, METAL)
		for _, sz in { -1, 1 } do
			K.block(model, "Idler", Cf * CFrame.new(sx * 3.1, 0.9, sz * 5), Vector3.new(2.3, 1.8, 1.8), RUBBER, { shape = Enum.PartType.Cylinder })
		end
		K.block(model, "TrackPad", Cf * CFrame.new(sx * 3.1, 1.84, 0), Vector3.new(2, 0.1, 9.6), K.pick(rng, RUST), nil)
	end
	K.block(model, "Carbody", Cf * CFrame.new(0, 1.6, 0), Vector3.new(4.2, 1, 5), STEEL_DARK, METAL)
	K.column(model, "Turntable", Cf * CFrame.new(0, 2.35, 0.5), 0.5, 5, STEEL, METAL)

	-- The house, its cab off the front left, the counterweight on the back.
	local house = Cf * CFrame.new(0, 4.4, 0.9)
	K.block(model, "House", house, Vector3.new(5.6, 3.6, 7.5), CRANE_PAINT, nil)
	K.block(model, "HouseRoof", house * CFrame.new(0, 1.85, 0), Vector3.new(5.4, 0.12, 7.2), CRANE_FADED, nil)
	for _ = 1, 3 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		K.block(model, "HouseRust", house * CFrame.new(side * 2.83, rng:NextNumber(-1, 1), rng:NextNumber(-3, 3)), Vector3.new(0.06, rng:NextNumber(0.6, 1.4), rng:NextNumber(0.8, 2)), K.pick(rng, RUST), nil)
	end
	local cab = Cf * CFrame.new(-3.9, 4.1, -2.1)
	K.block(model, "Cab", cab, Vector3.new(2.2, 3.2, 2.6), CRANE_PAINT, nil)
	K.block(model, "CabWindow", cab * CFrame.new(0, 0.5, -1.32), Vector3.new(1.8, 1.6, 0.06), WINDOW, nil)
	K.block(model, "CabSideWindow", cab * CFrame.new(-1.12, 0.5, 0), Vector3.new(0.06, 1.4, 1.9), WINDOW, nil)
	K.block(model, "Counterweight", Cf * CFrame.new(0, 3.9, 5.4), Vector3.new(5.8, 2.6, 1.6), K.hex("4E4A48"), STUDS)

	-- The A-frame gantry the boom's pendants run back to.
	local apex = (Cf * CFrame.new(0, 9.6, 2.4)).Position
	for _, sx in { -1, 1 } do
		strut(model, "Gantry", (Cf * CFrame.new(sx * 2, 6.2, 0.2)).Position, apex, 0.3, CRANE_FADED, METAL)
		strut(model, "Gantry", (Cf * CFrame.new(sx * 2, 6.2, 3.8)).Position, apex, 0.3, CRANE_FADED, METAL)
	end

	-- The boom: four chords and zig-zag lacing up both sides.
	local angle = rng:NextNumber(30, 36)
	local Lb = 24
	local Bm = Cf * CFrame.new(0, 4.6, -3.2) * CFrame.Angles(math.rad(angle), 0, 0)
	local w, h = 0.8, 0.8
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			K.block(model, "Chord", Bm * CFrame.new(sx * w, sy * h, -Lb / 2), Vector3.new(0.3, 0.3, Lb), CRANE_PAINT, METAL)
		end
		local pitch = 2
		for i = 0, math.floor(Lb / pitch) - 1 do
			local y1 = if i % 2 == 0 then -h else h
			strut(model, "Lacing", (Bm * CFrame.new(sx * w, y1, -i * pitch)).Position, (Bm * CFrame.new(sx * w, -y1, -(i + 1) * pitch)).Position, 0.16, CRANE_FADED, METAL)
		end
	end
	for i = 0, math.floor(Lb / 4) do
		strut(model, "Batten", (Bm * CFrame.new(-w, h, -i * 4)).Position, (Bm * CFrame.new(w, h, -i * 4)).Position, 0.16, CRANE_FADED, METAL)
	end
	local tip = Bm * CFrame.new(0, 0, -Lb)
	K.block(model, "BoomHead", tip, Vector3.new(2, 1.9, 0.8), CRANE_PAINT, METAL)
	K.block(model, "Sheave", tip * CFrame.new(0, 0.2, -0.6), Vector3.new(0.5, 1.6, 1.6), STEEL_DARK, { shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
	for _, sx in { -0.5, 0.5 } do
		strut(model, "Pendant", (tip * CFrame.new(sx, h, 0)).Position, apex + Vector3.new(0, 0, 0), 0.1, STEEL_DARK, METAL)
	end

	-- The hook, straight down off the tip, and the drum still slung under it.
	local over = (tip * CFrame.new(0, 0, -0.6)).Position
	local drumBase = Vector3.new(over.X, groundY + rng:NextNumber(1.8, 2.8), over.Z)
	local hookY = drumBase.Y + drums.h + 1.6
	K.block(model, "HookLine", CFrame.new(over.X, (over.Y + hookY) / 2, over.Z), Vector3.new(0.12, over.Y - hookY, 0.12), STEEL_DARK, METAL)
	K.block(model, "HookBlock", CFrame.new(over.X, hookY - 0.3, over.Z) * CFrame.Angles(0, math.rad(yaw), 0), Vector3.new(1, 1.2, 0.7), K.hex(DRUM_YELLOW), METAL)
	local drumCF = CFrame.new(drumBase) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(math.rad(rng:NextNumber(3, 7)), 0, 0)
	drums.build(model, drumCF, rng)
	local rim = drums.r * 0.85
	for _, sx in { -1, 1 } do
		strut(model, "Sling", Vector3.new(over.X, hookY - 0.9, over.Z), (drumCF * CFrame.new(sx * rim, drums.h, 0)).Position, 0.1, STEEL_DARK, METAL)
	end

	model.Parent = parent
end

-- ── Tyre ruts ──────────────────────────────────────────────────────────────────

--- A pair of ruts along the quadratic curve a → c → b, laid as short flat segments.
local function ruts(parent: Instance, a: Vector3, c: Vector3, b: Vector3, groundY: number, color: Color3, lift: number)
	local steps = math.max(3, math.floor(((c - a).Magnitude + (b - c).Magnitude) / 3))
	local function at(t: number): Vector3
		local u = 1 - t
		local p = a * (u * u) + c * (2 * u * t) + b * (t * t)
		return Vector3.new(p.X, groundY + 0.07 + lift, p.Z)
	end
	local prev = at(0)
	for i = 1, steps do
		local nxt = at(i / steps)
		local seg = nxt - prev
		local len = seg.Magnitude
		if len > 0.1 then
			local frame = CFrame.lookAt((prev + nxt) / 2, nxt)
			for _, side in { -1, 1 } do
				K.block(parent, "Rut", frame * CFrame.new(side * RUT_GAUGE / 2, 0, 0), Vector3.new(RUT_W, 0.02, len + 0.25), color, { shadow = false })
			end
		end
		prev = nxt
	end
end

-- ── Build ──────────────────────────────────────────────────────────────────────

--- Where the field's existing drums and carcasses landed, so nothing here is built
--- on top of them. Only the carcasses count, found by the parts only a carcass has
--- (build/Scenery's animalSkeleton): a handful of loose bone under a pallet is fine,
--- a spine through a crane is not. By NAME, not size -- a carcass is built from small
--- pieces, and a size filter (>= 3 studs) caught none of the spine that ran straight
--- through the first crane.
local CARCASS = { Vertebra = true, Rib = true, Pelvis = true, Jaw = true }

local function existing(parent: Instance): Taken
	local taken: Taken = {}
	local barrels = parent:FindFirstChild("Barrels")
	if barrels then
		for _, d in barrels:GetChildren() do
			if d:IsA("Model") then
				local p = d:GetPivot().Position
				table.insert(taken, { p.X, p.Z, 3 })
			end
		end
	end
	local bones = parent:FindFirstChild("Bones")
	if bones then
		for _, d in bones:GetDescendants() do
			if d:IsA("BasePart") and CARCASS[d.Name] then
				table.insert(taken, { d.Position.X, d.Position.Z, 2 })
			end
		end
	end
	return taken
end

--- Try up to 60 points from `gen` for one at least `r` clear of everything taken.
local function place(taken: Taken, r: number, gen: () -> (number, number)): (number, number)
	local x, z = gen()
	for _ = 1, 60 do
		if clearOf(taken, x, z, r) then
			break
		end
		x, z = gen()
	end
	return x, z
end

function WasteDump.build(parent: Instance, stageId: number, groundY: number, drums: Drums)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)
	local taken = existing(parent)

	local folder = Instance.new("Folder")
	folder.Name = "WasteDump"

	-- The two landmarks first, on opposite sides of the walk and at opposite ends: the
	-- crane in the east third with its boom swung back west over the field (so the hook
	-- hangs inside it and the drum on it faces the walk in), the truck in the west third.
	local craneSide = if rng:NextNumber() < 0.5 then -1 else 1
	local craneYaw = 90 - craneSide * rng:NextNumber(6, 18)
	local boomDir = CFrame.Angles(0, math.rad(craneYaw), 0).LookVector
	-- The hook hangs about 23 studs out along the boom; its drum has to land clear too,
	-- or the one drum that tells the story hangs in a carcass (shot live).
	local cx, cz = 0, 0
	for _ = 1, 60 do
		-- Off the field's own edge (was a flat 46-62, which the 124-wide stages put
		-- against the wall).
		cx, cz = rng:NextNumber(f.maxX - 60, f.maxX - 28), craneSide * rng:NextNumber(f.maxZ - 23, f.maxZ - 7)
		if clearOf(taken, cx, cz, 9) and clearOf(taken, cx + boomDir.X * 23, cz + boomDir.Z * 23, 6) then
			break
		end
	end
	crane(folder, Vector3.new(cx, groundY, cz), craneYaw, rng, drums)
	-- The crane's own footprint, and the ground under its boom out to the hook.
	for d = 0, 24, 8 do
		table.insert(taken, { cx + boomDir.X * d, cz + boomDir.Z * d, 7 })
	end

	local tx, tz = place(taken, 12, function()
		return rng:NextNumber(f.minX + 36, f.minX + 80), -craneSide * rng:NextNumber(36, 50)
	end)
	-- Backed in from the west: nose toward Stage 2 and the walk, tipped bed and its
	-- spilled load facing into the field. Turned the other way (shot live) the load
	-- piled up against the stage seam where nobody walking in could see it.
	local truckYaw = 90 + craneSide * rng:NextNumber(10, 30)
	local Tk = truck(folder, Vector3.new(tx, groundY, tz), truckYaw, rng, drums, palette)
	for _, z in { -4, 4, 12 } do
		local p = Tk * CFrame.new(0, 0, z)
		table.insert(taken, { p.X, p.Z, 8 })
	end

	-- Yards and trenches are dealt over a field pulled in from the plate's edges by
	-- their own reach, so a fence return or a spoil heap never hangs off the side.
	local inner = table.clone(f)
	inner.minX += 14
	inner.maxX -= 14
	inner.minZ += 9
	inner.maxZ -= 9

	-- The avoid radius is the yard's own half-width over each thing's clearance. At +14
	-- (the yard's full reach) the field's fourteen drums fenced off so much ground that
	-- only two of three yards found a site; a loose drum just outside a yard's fence
	-- reads as part of the dump anyway.
	local yards = K.sites(inner, YARDS, 44, rng, 12, (function()
		local avoid = {}
		for _, t in taken do
			table.insert(avoid, { t[1], t[2], (t[3] or 0) + 10 })
		end
		return avoid
	end)())
	for _, at in yards do
		yard(folder, at, rng, drums, taken)
	end

	local trenches = K.sites(inner, TRENCHES, 30, rng, 12, (function()
		local avoid = {}
		for _, t in taken do
			table.insert(avoid, { t[1], t[2], (t[3] or 0) + 9 })
		end
		return avoid
	end)())
	for i, at in trenches do
		trench(folder, at, rng, drums, palette, taken)
		-- Every other trench has a stretch of fence on its far side.
		if i % 2 == 1 then
			local out = if at.Z > 0 then 1 else -1
			local half = rng:NextNumber(7, 11)
			local a = at + Vector3.new(-half, 0, out * 6.5)
			local b = at + Vector3.new(half, 0, out * 6.5 + rng:NextNumber(-2, 2))
			fenceRun(folder, a, b, rng, drums, Vector3.new(0, 0, -out))
		end
	end

	-- The ruts: out of every yard and the truck, curving onto the walk.
	local track = Instance.new("Folder")
	track.Name = "Ruts"
	local sources: { Vector3 } = {}
	for _, at in yards do
		table.insert(sources, at + Vector3.new(0, 0, (if at.Z > 0 then -1 else 1) * 6.5))
	end
	table.insert(sources, (Tk * CFrame.new(0, 0, -9)).Position)
	for i, a in sources do
		local side = if a.Z > 0 then 1 else -1
		local b = Vector3.new(a.X + rng:NextNumber(-30, 30), groundY, side * rng:NextNumber(0, 5))
		local c = Vector3.new(a.X + rng:NextNumber(-6, 6), groundY, (a.Z + b.Z) / 2)
		b = Vector3.new(math.clamp(b.X, f.minX, f.maxX), groundY, b.Z)
		ruts(track, a, c, b, groundY, palette.rut, (i % 3) * 0.003)
	end
	track.Parent = folder

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z)
		local roll = rng:NextNumber()
		if not clearOf(taken, x, z, 3) then
			return
		end
		local lane = K.onLane(z, 2)
		if roll < CRUSHED_CHANCE then
			if not lane then
				crushedDrum(ground, x, z, groundY, rng)
			end
		elseif roll < CRUSHED_CHANCE + LID_CHANCE then
			lid(ground, x, z, groundY, rng)
		elseif roll < CRUSHED_CHANCE + LID_CHANCE + TYRE_CHANCE then
			if not lane then
				tyres(ground, x, z, groundY, 2, rng)
			end
		elseif roll < CRUSHED_CHANCE + LID_CHANCE + TYRE_CHANCE + SLUDGE_CHANCE then
			sludge(ground, x, z, groundY, rng:NextNumber(2.5, 5), rng)
		end
	end)
	ground.Parent = folder

	-- Walk-through and query-transparent, the drums included (Scenery's builder does
	-- not set CanQuery itself; scatterBarrels clears it after the fact the same way).
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	folder.Parent = parent
end

return WasteDump
