--!strict
--[[
	ItemCrust.luau — the shell of irradiated slag an item comes out of the ground in.

	WHAT YOU DIG UP IS NOT AN ITEM YET. It is a lump: fallout-baked soil and slag fused
	around whatever the magnet found, and until the hose takes that off you do not know
	what you have. The bag calls it "???", the banner names a rarity and nothing else,
	and the object in your hand is a rock. Cleaning it IS the reveal — that is the whole
	loop this module exists to make visible.

	A SHELL, NOT A FILM. This replaces Shared/ItemGrime, which tinted the item's own
	parts green and left every silhouette perfectly readable: a Gold Ring dug up looking
	exactly like a Gold Ring, only greener. Colour cannot hide identity, because SHAPE is
	identity. So the item is wrapped in real geometry instead — chunks of rock big enough
	to swallow its outline, which the water then takes off a piece at a time.

	ONE CHUNK, ONE PATCH. `encase` builds exactly as many chunks as the item has
	contamination patches (Shared/Contamination), spread around it on the golden-angle
	spiral so each one owns a different side. That is what makes the wash bay's aim game
	work on a crusted object: the thing you point the hose at is a real lump on a real
	side of the item, it visibly erodes as it soaks, and when its patch finally pops the
	chunk comes off and the item shows through the gap. Six patches is six chunks and six
	stages of reveal; one patch is one shell that breaks all at once.

	IT IS ALSO WHAT YOU CARRY. ToolService encases the model in your off hand with a
	chunk per REMAINING patch, so an item you half-cleaned and walked away from is half
	emerged in your hand. The lump in the ground (`lump`) is the one deliberate exception
	— it is always fully crusted, because grading it by the roll would leak Prewar
	Sealed's "needs no cleaning" before the reveal is supposed to happen at all.

	RARITY IS THE ONE THING THE ROCK IS ALLOWED TO SAY. The detector already told the
	player what tier they are hauling and the banner repeats it, so hiding it here would
	be a lie the rest of the UI immediately contradicts. The slag is cast a little of the
	way toward the rarity colour and lit by one faint PointLight of it — a Legendary lump
	reads warm against the soil and a Scrap one reads like a stone, without either turning
	into a coloured toy. Everything else about the item — name, flavour, what it is worth,
	what it looks like — stays under the rock.

	STASH-AND-RESTORE, THE SAME DEAL ITEMGRIME MADE. `erode` re-derives from the size and
	colour stashed on each part the first time it touched it, never from what is on the
	part now, so calling it every tick with a falling level walks the chunk down smoothly
	instead of compounding a shrink onto a shrink.
]]

local Rarity = require(script.Parent.Config.Rarity)

local ItemCrust = {}

--- Fallout-baked soil: dry, cold and dark, but not black. It sat at 3A362F for a build
--- and the trouble with a near-black base is that everything else lands on top of it —
--- the rarity tint and the rarity light both read as THE colour rather than as a cast
--- over stone, and a Rare find came up navy.
local ROCK = Color3.fromHex("4A453C")

--- What an unknown rarity gets. Only reachable from a caller that has no reading at
--- all; every real dig has one by the time a lump is built.
local NEUTRAL = Color3.fromHex("6E6A62")

--- How far toward the rarity colour the slag is dragged. An EIGHTH, and it was a fifth
--- for one build: against a near-black base a fifth of a saturated blue is not a tint,
--- it is the colour, and a Rare find came up looking like a navy crate rather than like
--- rock with something in it. Low enough to read as a cast over stone, high enough that
--- a Legendary lump is visibly not a Common one at ten studs.
local RARITY_TINT = 0.13

--- Per-piece brightness jitter, so a chunk is a pile of different stones rather than
--- one colour repeated.
local SHADE_JITTER = 0.26

--- Pieces per chunk. One box reads as a crate; three overlapping boxes at broken
--- angles read as rubble, which is the whole difference between "this is encrusted"
--- and "this is in a box".
local PIECES = 3

--- How far off the item's centre a chunk sits, as a fraction of the item's own half
--- extent. Small on purpose: chunks have to OVERLAP into a shell, and a spread wide
--- enough to give each one its own clean territory leaves gaps you can read the item
--- through on the first tick.
local REACH = 0.42

--- Chunk size as a fraction of the item's own extent ON EACH AXIS: a floor plus a share
--- that shrinks as the count rises, so two chunks are each most of a shell and six are
--- each a patch of one.
---
--- PER AXIS, NOT OFF THE LARGEST ONE, and the first build got that wrong. Sizing every
--- piece off the biggest dimension turns a flat object into a cube of rubble twice the
--- width of the thing inside it — a Gold Ring came up wearing a four-stud boulder. Taken
--- per axis the crust HUGS what it is hiding: a flat item grows a flat crust, and the
--- lump is recognisably the size and shape of the thing you are about to uncover.
---
--- WHY THE FLOOR IS AS HIGH AS IT IS, and it is the number to be careful with. A chunk
--- sits at most REACH of the way out from the centre, so it reaches the far end of its
--- own axis only if its half-size covers the rest: 1 - REACH of the half extent, before
--- any allowance for a spiral direction that does not point straight down that axis. Cut
--- below that and long items stop being covered end to end — the build that got this
--- wrong put a Steel Rod in a crust that swallowed one end and left three studs of rod
--- hanging out of it, which is the entire feature failing in the most visible way it can.
local COVER_BASE = 0.76
local COVER_PER_CHUNK = 0.45

--- ...and no axis of a piece may be thinner than this share of the item's mean extent.
--- Pieces cut exactly to a long item's aspect are all the same thin splinter, and a
--- bundle of splinters reads as laminate rather than as rock. This only ever FATTENS a
--- piece — it can never shorten the axis the coverage rule above depends on.
local MIN_ASPECT = 0.55

--- A thin object (a bottle cap is millimetres through) still has to grow a lump you
--- can point a hose at, so the body used for all of the above is never smaller than
--- this in any axis.
local MIN_BODY = 0.9

--- How small a chunk gets before its patch finally pops. Not to nothing: a chunk that
--- faded to zero would have the last second of work land on something invisible.
local SHRINK_FLOOR = 0.42

--- How see-through a fully soaked chunk goes on its way out. Wet slag, sloughing off.
local WET_FADE = 0.3

--- ...and how much darker. Wet rock is darker rock, and it is the only cue that
--- separates "I have soaked this one" from "I have not started" at a glance.
local WET_DARKEN = 0.35

local GLOW_NAME = "CrustGlow"
local SIZE_ATTR = "CrustSize"
local COLOR_ATTR = "CrustColor"

local GOLDEN = 2.39996323

--- A stable integer for `Random.new` out of whatever the caller has to identify this
--- item with — a carry uid, usually. Same item, same rubble, every time it is rebuilt:
--- the lump you hauled up, the lump in your hand and the lump on the tub are one
--- object, and re-rolling the shape at each hand-off would say otherwise.
local function seedOf(seed: (string | number)?): number
	if type(seed) == "number" then
		return seed
	end
	if type(seed) ~= "string" then
		return 0
	end
	local total = 0
	for index = 1, #seed do
		total = (total * 31 + string.byte(seed, index)) % 2147483647
	end
	return total
end

--- `count` directions spread over a sphere, golden-angle — the same construction the
--- wash bay used for its zone seeds, kept because it is the only cheap way to put N
--- points on a sphere without N of them bunching at the poles.
local function spiralDir(index: number, count: number): Vector3
	local t = (index - 0.5) / math.max(count, 1)
	local y = 1 - 2 * math.min(t, 1)
	local radius = math.sqrt(math.max(0, 1 - y * y))
	local theta = GOLDEN * index
	return Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
end

local function rockShade(rng: Random, accent: Color3): Color3
	local shade = 1 - SHADE_JITTER * 0.5 + rng:NextNumber() * SHADE_JITTER
	local base = Color3.new(
		math.clamp(ROCK.R * shade, 0, 1),
		math.clamp(ROCK.G * shade, 0, 1),
		math.clamp(ROCK.B * shade, 0, 1)
	)
	return base:Lerp(accent, RARITY_TINT)
end

local function slagPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Slate
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- CanQuery STAYS ON, and it is the one property here that is load-bearing rather
	-- than cosmetic: WashController answers "what did the water just hit" with a
	-- raycast, and a chunk the ray passes through is a chunk you cannot aim at.
	part.Parent = parent
	return part
end

--- The shared core: `count` chunks of rubble around `pivot`, sized off `body`.
local function buildChunks(
	parent: Instance,
	count: number,
	pivot: CFrame,
	body: Vector3,
	accent: Color3,
	rng: Random
): ({ [number]: { BasePart } }, { [number]: Vector3 })
	local cover = COVER_BASE + COVER_PER_CHUNK / math.max(count, 1)
	local floor = ((body.X + body.Y + body.Z) / 3) * MIN_ASPECT
	local span = Vector3.new(
		math.max(body.X, floor),
		math.max(body.Y, floor),
		math.max(body.Z, floor)
	) * cover
	local reach = body * 0.5 * REACH
	local wobble = body * 0.09

	local zones: { [number]: { BasePart } } = {}
	local anchors: { [number]: Vector3 } = {}

	for index = 1, count do
		local centre = pivot * CFrame.new(spiralDir(index, count) * reach)
		local zone: { BasePart } = {}

		for piece = 1, PIECES do
			-- Each piece is its own box, nudged off the chunk's centre and turned to a
			-- broken angle. Kept under 40 degrees: a cube rotated to 45 spans half again
			-- its own width on the diagonal, and three of those turn a crust into a
			-- spiky star.
			local offset = CFrame.new(
				rng:NextNumber(-wobble.X, wobble.X),
				rng:NextNumber(-wobble.Y, wobble.Y),
				rng:NextNumber(-wobble.Z, wobble.Z)
			)
			-- Kept under 25 degrees now that pieces are shaped like the item rather than
			-- cubed: a flat slab turned as far as a cube can be swings its corners clean
			-- out of the silhouette it is supposed to be filling.
			local turn = CFrame.Angles(
				math.rad(rng:NextNumber(-24, 24)),
				math.rad(rng:NextNumber(-24, 24)),
				math.rad(rng:NextNumber(-24, 24))
			)
			-- Jitter UP more than down, for the same coverage reason the floor above exists:
			-- the span is already close to the smallest piece that reaches the ends, so a
			-- generous shrink on the wrong axis is a gap.
			local size = Vector3.new(
				span.X * rng:NextNumber(0.92, 1.16),
				span.Y * rng:NextNumber(0.92, 1.16),
				span.Z * rng:NextNumber(0.92, 1.16)
			)
			table.insert(
				zone,
				slagPart(`Crust{index}_{piece}`, size, centre * offset * turn, rockShade(rng, accent), parent)
			)
		end

		zones[index] = zone
		anchors[index] = centre.Position
	end

	return zones, anchors
end

--- Hang one faint light of the rarity colour on the lump. One, on the whole model, not
--- one per chunk: six PointLights inside each other is six shadow-free lights doing the
--- work of one and costing six.
local function glow(root: Instance, accent: Color3, size: number)
	local anchor: BasePart? = if root:IsA("BasePart")
		then root
		else (if root:IsA("Model") and root.PrimaryPart then root.PrimaryPart else root:FindFirstChildWhichIsA("BasePart", true))
	if anchor == nil then
		return
	end

	local existing = anchor:FindFirstChild(GLOW_NAME)
	local light: PointLight
	if existing and existing:IsA("PointLight") then
		light = existing
	else
		light = Instance.new("PointLight")
		light.Name = GLOW_NAME
		light.Shadows = false
		light.Parent = anchor
	end
	-- FAINT. It is a seam of fallout showing through the rock, not a lamp inside it: at
	-- 0.9 this light was bright enough to paint every chunk around it in the rarity
	-- colour from the inside, which is how the first build turned a Rare lump into a navy
	-- crate. Low enough now that in daylight you barely register it and in a dark stage it
	-- is the thing that makes a Legendary worth walking toward.
	light.Color = accent
	light.Brightness = 0.3
	light.Range = math.clamp(size * 2, 3, 6)
end

--- Wrap `model` in `count` chunks of slag, parented into the model itself so anything
--- that moves the item — the tub's turntable, the weld into a hand — carries the crust
--- with it for free.
---
--- Returns one list of parts per chunk (the wash bay's zones, in the order the patches
--- were rolled) and the world point each chunk was built around (its ball's anchor, and
--- the fallback the aim raycast rounds to).
function ItemCrust.encase(
	model: Model,
	count: number,
	rarityName: string?,
	seed: (string | number)?
): ({ [number]: { BasePart } }, { [number]: Vector3 })
	local accent = if rarityName then Rarity.get(rarityName).color else NEUTRAL
	local pivot, size = model:GetBoundingBox()
	local body = Vector3.new(
		math.max(size.X, MIN_BODY),
		math.max(size.Y, MIN_BODY),
		math.max(size.Z, MIN_BODY)
	)

	local zones, anchors = buildChunks(model, math.max(count, 1), pivot, body, accent, Random.new(seedOf(seed)))
	glow(model, accent, math.max(body.X, body.Y, body.Z))

	return zones, anchors
end

--- A lump with nothing in it: what breaks the surface on a haul, before the item it is
--- wrapped around is any of the player's business. Always the same chunk count, always
--- fully crusted — see the header for why this one may not be graded by the roll.
function ItemCrust.lump(rarityName: string?, seed: (string | number)?): Model
	local model = Instance.new("Model")
	model.Name = "Crust"

	local accent = if rarityName then Rarity.get(rarityName).color else NEUTRAL
	local body = Vector3.new(1.3, 1.3, 1.3)
	local zones = buildChunks(model, 4, CFrame.new(), body, accent, Random.new(seedOf(seed)))

	-- SOMETHING TO PIVOT AND WELD BY. ToolService welds every other part to the
	-- primary before it lets go of the anchor, and a model with no PrimaryPart makes
	-- that choice by whatever GetDescendants happens to return first.
	local first = zones[1] and zones[1][1]
	model.PrimaryPart = first or model:FindFirstChildWhichIsA("BasePart")
	glow(model, accent, body.X)
	return model
end

--- Erode one chunk. `level` is 1 for untouched slag and 0 for a chunk about to come
--- off; `blocked` means this liquid cannot shift it at all, so it stays dry, dark and
--- full size no matter how long the stream sits on it — the potency wall, shown rather
--- than written on a label.
function ItemCrust.erode(parts: { BasePart }, level: number, blocked: boolean)
	local amount = math.clamp(level, 0, 1)
	for _, part in parts do
		local storedSize = part:GetAttribute(SIZE_ATTR)
		if typeof(storedSize) ~= "Vector3" then
			storedSize = part.Size
			part:SetAttribute(SIZE_ATTR, storedSize)
		end
		local storedColor = part:GetAttribute(COLOR_ATTR)
		if typeof(storedColor) ~= "Color3" then
			storedColor = part.Color
			part:SetAttribute(COLOR_ATTR, storedColor)
		end

		local baseSize = storedSize :: Vector3
		local baseColor = storedColor :: Color3

		if blocked then
			part.Size = baseSize
			part.Transparency = 0
			part.Color = baseColor:Lerp(Color3.new(0, 0, 0), 0.35)
			part.Material = Enum.Material.Slate
		else
			local soaked = 1 - amount
			part.Size = baseSize * (SHRINK_FLOOR + (1 - SHRINK_FLOOR) * amount)
			part.Transparency = soaked * WET_FADE
			part.Color = baseColor:Lerp(Color3.new(0, 0, 0), soaked * WET_DARKEN)
			part.Material = Enum.Material.Rock
		end
	end
end

--- That patch is gone: take its chunk off the item. There is nothing to restore and no
--- fade — the slag was ON the object, and the object underneath is the point.
function ItemCrust.strip(parts: { BasePart })
	for _, part in parts do
		part:Destroy()
	end
end

--- Nothing left to hide: put the light out. Called when the last patch clears, so an
--- item standing revealed on the tub is lit by the bay and not by its own fallout.
function ItemCrust.clear(root: Instance)
	if root:IsA("BasePart") then
		local own = root:FindFirstChild(GLOW_NAME)
		if own then
			own:Destroy()
		end
	end
	for _, descendant in root:GetDescendants() do
		if descendant.Name == GLOW_NAME and descendant:IsA("PointLight") then
			descendant:Destroy()
		end
	end
end

return ItemCrust
