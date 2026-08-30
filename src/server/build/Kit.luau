--!strict
--[[
	Kit.luau — the primitives every world generator is built from.

	WHY THIS EXISTS
	These functions were private to BaseCamp.luau, which was fine while the camp was
	the only generated structure in the world. It no longer is: the hub, the shops,
	the plots, the stage plates and the scenery are all built the same way, and four
	copies of a part-builder is how they quietly drift apart.

	Everything here except `swap`, `stamp` and `surfaceText` is lifted from
	BaseCamp.luau VERBATIM — same numbers, same strings, same behaviour. That was
	deliberate: the camp is the one piece of geometry in this project that has been
	diffed against the live place to the stud, and the extraction had to be provably
	neutral before anything new was built on top of it.

	THE IMPORTANT ONE IS `swap`.
	BaseCamp.rebuild() had a genuinely valuable safety property — build the new thing
	unparented, and only then destroy and replace the old one, so an error in the
	middle of a bad edit cannot leave you with no camp. That property used to live
	inside one function. Generalised here, every generator gets it for free instead
	of half-reimplementing it.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Kit = {}

--- Tag applied to every part carrying a StationKind attribute. StationService reads
--- the tag so it can scan O(#stations) instead of walking all of Workspace ten times
--- a second. THE ATTRIBUTE REMAINS THE SOURCE OF TRUTH — the tag is only an index,
--- and World.verify() asserts the two never disagree.
Kit.STATION_TAG = "Station"
Kit.SHOWER_TAG = "Shower"

-- ── Palette ───────────────────────────────────────────────────────────────────
-- Named so a re-skin is one edit rather than a find-and-replace over hex codes.
--
-- The first block is the base camp's original palette, unchanged — the camp still
-- looks exactly as it did. The second is the bright outdoor world (PLAN §14, as
-- rewritten): saturated everywhere, and radiation is the only thing that GLOWS.
-- Nothing outside a stage may use Material.Neon in acid green; that channel means
-- danger and it stays uncontaminated.
Kit.C = {
	-- Base camp (original values — do not repaint without rebuilding the camp)
	floor = "C9C4B8",
	concrete = "8E9689",

	wood = "5A4630",
	woodLight = "A9743F",
	canvas = "E0A33C",
	canvasPale = "EFE3C8",
	gold = "F0C64B",

	steel = "9FB6C4",
	steelDark = "4A5560",
	showerSteel = "42505C",
	drain = "2C363F",

	cyan = "7FD0FF",
	glass = "BFE6FF",
	hazard = "E8C33C",
	hazardBlack = "1A1A1A", -- crisp cartoon black for trefoil blades and outline trim

	labelText = "F2F5EE",
	signText = "2B2415",
	lampWarm = "FFD9A0",

	-- The bright world
	skyMint = "BFF3E4",
	plazaWarm = "F2E3B8",
	plazaEdge = "D8C79A",

	-- The exhibition plinths on the plots (Plots.buildDisplayStand). Mid neutral
	-- grey, deliberately the one grey object standing on a base that is otherwise
	-- navy-and-grey tiles — a two-course studded riser reads as built furniture, not
	-- poured ground. `standGreyDark` is the base course, `standGrey` the top course
	-- and its frame, so the stack reads as lit from above. NOT a hazard channel:
	-- never Neon, never one of the ooze greens.
	standGrey = "A0A0A0",
	standGreyDark = "787878",

	-- ── The checkerboard, in its two palettes ────────────────────────────────
	-- One pattern, one grid, two colour schemes: the plaza and its apron in green,
	-- the six player bases in navy and grey, a step above it. Walking onto a base
	-- changes the colour under your feet without breaking the board — the tiles stay
	-- in register across the edge because the grid is the plaza's for both.
	--
	-- THE GREENS ARE DELIBERATELY DESATURATED, and that is not a taste call. Green is
	-- spoken for in this world: "the paths are safe, the green is not" is the rule the
	-- hub's own header calls the most legible thing in the game. The radiation fields
	-- are saturated yellow-green under glowing Neon; these are muted, cool and matte,
	-- and they are laid in a hard-edged studded grid that no field has. That is what
	-- keeps a green courtyard from reading as ground you should not stand on. Do not
	-- brighten them toward the fields.
	plazaTileDark = "3F5E3A",
	plazaTileLight = "486B42",

	-- The bases. These are the colours the plaza wore first — a base is now the one
	-- place in the world that is not some shade of green.
	baseTileDark = "212639",
	baseTileLight = "545A66",
	grass = "8FD86A",
	grassDark = "6FB84E",
	road = "E8DCC0",

	-- Radiation. The ONLY Neon green in the world.
	--
	-- These are green-DOMINANT on purpose. Neon renders a colour at full emission and
	-- bloom pushes it further, so a yellow-green like B6FF6E comes out of the pipeline
	-- as cream and stops reading as toxic at all. Keep red well under green here or
	-- the ooze turns into custard.
	--
	-- THESE THREE ARE NO LONGER THE WHOLE HAZARD CHANNEL. They are stages 1-3's share
	-- of it. From Stage 4 the fields turn plum, hot pink and violet, and each stage
	-- carries its own bright/deep/glow triple in Config/Stages (`StageDef.ooze`) — which
	-- is where to go to retune a field, not here. These stay because the greens are
	-- still what three of the six stages are painted in, and because the rule they
	-- encode travels: keep the dominant channel dominant or bloom eats the colour.
	--
	-- What is still absolute is the OTHER half of the original rule: nothing OUTSIDE a
	-- stage may use Material.Neon in any of these hazard colours. That channel means
	-- danger and it stays uncontaminated — the shop signs and the plot accents are
	-- bright, but never in these.
	ooze = "4FD11A",
	oozeBright = "6BEE2E",
	oozeDeep = "2A6B10",

	barrelYellow = "F2C33C",
	barrelRust = "E2603C",
	rubble = "A8A093",

	-- Shop identity colours. A young player learns "the coral one is the detector
	-- shop" once and navigates by it forever, which is the single biggest
	-- legibility win available for the price.
	shopDetector = "FF7A5C",
	shopMagnet = "4CC9F0",
	shopCleaner = "B15CFF",
	shopOutfitter = "FFC93C",
}

--- Per-plot accent colours. Index by plot number.
Kit.PLOT_ACCENT = { "FF6B9D", "4CC9F0", "FFC93C", "7CE05A", "FF9F45", "B15CFF" }

-- ── Orientations ──────────────────────────────────────────────────────────────
-- Degrees, XYZ euler. A Roblox Cylinder's axis is its X size, so "upright" means
-- rotating X onto Y.
function Kit.ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

Kit.R = {
	flat = Kit.ang(0, 0, 0),
	yaw180 = Kit.ang(-180, 0, -180), -- same box, facing the other way
	yaw90 = Kit.ang(0, 90, 0),
	yaw270 = Kit.ang(0, -90, 0),
	cylUp = Kit.ang(0, 0, 90), -- cylinder standing upright
	cylUpFlipped = Kit.ang(-180, 0, -90), -- upright, yawed 180 (invisible on a cylinder, kept for fidelity)
	cylAlongZ = Kit.ang(90, 90, 0), -- cylinder lying front-to-back
	cylAlongX = Kit.ang(0, 0, 0), -- cylinder lying left-to-right (its native axis)
	lidTilt = Kit.ang(-125, 0, -180), -- the cash box lid, propped open
}

-- ── Oriented-rectangle geometry ─────────────────────────────────────────────
-- For pads whose facing is no longer a multiple of 90 (the semicircular base
-- ring): a plain axis-aligned bounding box is wrong at an arbitrary yaw, so
-- overlap/containment tests need the pad's real, rotated footprint.

export type OrientedRect = {
	cx: number,
	cz: number,
	halfWidth: number, -- half-extent along the rect's own local X
	halfDepth: number, -- half-extent along the rect's own local Z
	yawDeg: number, -- same convention as a pad's `facing`
}

--- The four corners of a rotated rectangle, in world XZ. At yawDeg = 0/90/180/-90
--- this reduces to exactly the same 4 points the old axis-aligned
--- "swap width/depth" trick produced -- cos/sin of a multiple of 90 degrees is
--- exactly 0 or +/-1, so nothing here is a new answer for the old cases, only a
--- generalisation to angles they never had to handle.
function Kit.orientedRectCorners(r: OrientedRect): { { number } }
	local th = math.rad(r.yawDeg)
	local c, s = math.cos(th), math.sin(th)
	local pts = {}
	for _, lx in { -r.halfWidth, r.halfWidth } do
		for _, lz in { -r.halfDepth, r.halfDepth } do
			table.insert(pts, { r.cx + lx * c + lz * s, r.cz - lx * s + lz * c })
		end
	end
	return pts
end

--- Whether a world point falls inside a rotated rectangle: rotate the point INTO
--- the rectangle's own local frame (the inverse of the rotation `build` applies),
--- then a plain axis-aligned bounds check. Strict `<`, so a point exactly on the
--- edge counts as outside -- the same convention the old apron `insidePad` check
--- used (`x > x0 and x < x1`).
function Kit.pointInOrientedRect(x: number, z: number, r: OrientedRect): boolean
	local th = math.rad(r.yawDeg)
	local c, s = math.cos(th), math.sin(th)
	local dx, dz = x - r.cx, z - r.cz
	local lx = c * dx - s * dz
	local lz = s * dx + c * dz
	return lx > -r.halfWidth and lx < r.halfWidth and lz > -r.halfDepth and lz < r.halfDepth
end

--- Separating-axis test for two rectangles at arbitrary yaws. Two rectangles have
--- only 4 candidate separating axes between them (each one's own two face
--- normals) -- if the rectangles' projections onto EVERY one of those 4 axes
--- overlap, the rectangles overlap; if any single axis separates them, they do
--- not. `<=` counts as touching, not overlapping -- the direct generalisation of
--- World.luau's own axis-aligned `rectsOverlap`, which already treats an
--- exactly-shared edge as legal (that's what makes the plaza/Stage-1 shared edge
--- safe today).
function Kit.orientedRectsOverlap(a: OrientedRect, b: OrientedRect): boolean
	local function axes(r: OrientedRect): { { number } }
		local th = math.rad(r.yawDeg)
		local c, s = math.cos(th), math.sin(th)
		return { { c, -s }, { s, c } }
	end

	local cornersA, cornersB = Kit.orientedRectCorners(a), Kit.orientedRectCorners(b)
	for _, ax in { axes(a)[1], axes(a)[2], axes(b)[1], axes(b)[2] } do
		local aLo, aHi = math.huge, -math.huge
		for _, p in cornersA do
			local d = p[1] * ax[1] + p[2] * ax[2]
			aLo, aHi = math.min(aLo, d), math.max(aHi, d)
		end
		local bLo, bHi = math.huge, -math.huge
		for _, p in cornersB do
			local d = p[1] * ax[1] + p[2] * ax[2]
			bLo, bHi = math.min(bLo, d), math.max(bHi, d)
		end
		if aHi <= bLo or bHi <= aLo then
			return false
		end
	end
	return true
end

-- ── Builders ──────────────────────────────────────────────────────────────────

export type Spec = {
	name: string,
	pos: { number }, -- {x, y, z} relative to origin
	size: { number },
	color: string,
	material: string,
	rot: CFrame?,
	shape: string?, -- "Block" (default) | "Cylinder" | "Ball" | "Wedge"
	transparency: number?,
	canCollide: boolean?,
	studs: boolean?, -- stud every face (forces Material.Plastic — studs render on nothing else)
	class: string?, -- "Part" (default) | "SpawnLocation" | "WedgePart"
	attributes: { [string]: any }?,
}

function Kit.build(parent: Instance, origin: CFrame, spec: Spec): BasePart
	local p = Instance.new(spec.class or "Part") :: any
	p.Name = spec.name
	p.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	p.Color = Color3.fromHex(spec.color)
	p.Material = Enum.Material[spec.material]
	p.Transparency = spec.transparency or 0
	p.Anchored = true
	p.CanCollide = if spec.canCollide == nil then true else spec.canCollide

	if p:IsA("Part") then
		p.Shape = Enum.PartType[spec.shape or "Block"]
	end

	-- Studs need Material.Plastic AND every face set explicitly -- only TopSurface is
	-- Studs by default on a fresh Part (see Hub.tileRect). This forces both, so a caller
	-- gets the studded-brick look whatever material it happened to name.
	if spec.studs then
		p.Material = Enum.Material.Plastic
		for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do
			p[face] = Enum.SurfaceType.Studs
		end
	end

	p.CFrame = origin * CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3]) * (spec.rot or Kit.R.flat)

	for key, value in spec.attributes or {} do
		p:SetAttribute(key, value)
	end

	-- Index the interactive parts as they are created. Doing this here rather than
	-- in a post-pass means a station can never exist untagged, which is the failure
	-- mode that would present as "this one shop just doesn't work".
	if p:GetAttribute("StationKind") ~= nil then
		CollectionService:AddTag(p, Kit.STATION_TAG)
	end
	if p:GetAttribute("Shower") == true then
		CollectionService:AddTag(p, Kit.SHOWER_TAG)
	end

	p.Parent = parent
	return p
end

--- Blend two hex colours, `t` = 0 -> a, 1 -> b. Used to bake a stage's bright
--- ooze tint straight into a ground colour instead of layering a separate
--- translucent plate over it (see Stages.GROUND_OOZE_TINT).
function Kit.blendHex(a: string, b: string, t: number): string
	return Color3.fromHex(a):Lerp(Color3.fromHex(b), t):ToHex()
end

function Kit.light(part: BasePart, color: string, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex(color)
	l.Range = range
	l.Brightness = brightness
	l.Parent = part
end

--- The floating "TRADER / turn it into cash" card over each station.
---
--- `maxDistance` defaults to 40 studs -- far enough to read the label while
--- you're still walking up, close enough that it isn't cluttering the screen
--- from clear across the plaza or the field. `math.huge` (every label, every
--- station, visible from anywhere) was the previous behaviour and is exactly
--- the "taking up a lot of screen real estate" complaint this fixes.
function Kit.billboard(part: BasePart, width: number, height: number, title: string, subtitle: string, subColor: string, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 40
	gui.Parent = part

	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, 0, 0, 30)
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.GothamBold
	head.TextSize = 22
	head.TextColor3 = Color3.fromHex(Kit.C.labelText)
	head.TextStrokeTransparency = 0.4
	head.Text = title
	head.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromOffset(0, 28)
	sub.Size = UDim2.new(1, 0, 0, 20)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 14
	sub.TextColor3 = Color3.fromHex(subColor)
	sub.TextStrokeTransparency = 0.5
	sub.Text = subtitle
	sub.Parent = gui
end

--- Painted text on a face — the BASE CAMP sign, stage border warnings, plot names.
function Kit.surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: string, alwaysOnTop: boolean?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	-- PixelsPerStud is silently IGNORED unless SizingMode is explicitly set to
	-- use it -- the default SizingMode uses a fixed square-ish CanvasSize no
	-- matter what shape the part's face actually is. Every non-square sign in
	-- the game (any board wider than it is tall, which is all of them) was
	-- laying text out on that square canvas and then stretching the whole thing
	-- onto the real, much wider face -- the actual cause of "the text itself
	-- looks stretched horizontally," not the board's own proportions.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = alwaysOnTop or false
	-- Several callers (Shops.luau's signs) attach a PointLight to this same part
	-- for the "glowing sign" look. LightInfluence defaults to 1, so that light
	-- was blowing its own text out to a blank wash right next to the source.
	-- Text should read the same whether or not the part happens to glow.
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex(color)
	label.TextStrokeTransparency = 1
	label.Text = text
	label.Parent = gui
	return label
end

--- Mark a generated structure so a stray hand-edit is identifiable later, and so
--- nobody has to guess which file to edit to change what they are looking at.
function Kit.stamp(model: Instance, source: string, version: number)
	model:SetAttribute("GeneratedBy", source)
	model:SetAttribute("BuilderVersion", version)
end

--- Replace `Workspace.<name>` with a freshly built version, atomically.
---
--- `factory` must return a fully-formed, UNPARENTED instance. It is called first
--- and its result is only swapped in once it has returned — so if a bad edit throws
--- halfway through, the structure currently in the world survives untouched. That
--- is the whole point, and it is why generators should never parent as they go.
function Kit.swap(name: string, factory: () -> Instance, parent: Instance?): Instance
	local built = factory()
	built.Name = name

	local target = parent or Workspace
	local existing = target:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	built.Parent = target
	return built
end

--- Every BasePart under `root` carrying `attribute`. Used by verification.
function Kit.partsWithAttribute(root: Instance, attribute: string): { BasePart }
	local found = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(attribute) ~= nil then
			table.insert(found, d)
		end
	end
	return found
end

return Kit
