--!strict
--[[
	Kit.luau — the primitives every world generator is built from.

	WHY THIS EXISTS
	These functions were private to BaseCamp.luau, which was fine while the camp was
	the only generated structure in the world. It no longer is: the hub, the shops,
	the plots, the zone plates and the scenery are all built the same way, and four
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
-- Nothing outside a zone may use Material.Neon in acid green; that channel means
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

	labelText = "F2F5EE",
	signText = "2B2415",
	lampWarm = "FFD9A0",

	-- The bright world
	skyMint = "BFF3E4",
	plazaWarm = "F2E3B8",
	plazaEdge = "D8C79A",
	grass = "8FD86A",
	grassDark = "6FB84E",
	road = "E8DCC0",

	-- Radiation. The ONLY Neon green in the world.
	--
	-- These are green-DOMINANT on purpose. Neon renders a colour at full emission and
	-- bloom pushes it further, so a yellow-green like B6FF6E comes out of the pipeline
	-- as cream and stops reading as toxic at all. Keep red well under green here or
	-- the ooze turns into custard.
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

function Kit.light(part: BasePart, color: string, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex(color)
	l.Range = range
	l.Brightness = brightness
	l.Parent = part
end

--- The floating "TRADER / turn it into cash" card over each station.
function Kit.billboard(part: BasePart, width: number, height: number, title: string, subtitle: string, subColor: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = math.huge
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

--- Painted text on a face — the BASE CAMP sign, zone border warnings, plot names.
function Kit.surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: string, alwaysOnTop: boolean?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = alwaysOnTop or false
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
