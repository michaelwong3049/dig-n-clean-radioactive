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

	ONE CHUNK, ONE PATCH -- AND A CHUNK IS A PILE OF ROCKS. `encase` tiles the item's
	box with about ROCK_BUDGET small rocks and deals them out to as many chunks as the
	item has contamination patches (Shared/Contamination), each chunk owning the side of
	the item nearest its own golden-angle direction. The patch is still the unit of
	balance -- one clock, one charge, one weak point -- but the rock is the unit you
	SEE: as a chunk soaks, its rocks break off one at a time starting from wherever the
	water is landing (`erode`'s `near`), so washing is sweeping the stream across the
	item picking off pebbles, not staring at one boulder until it vanishes. The last
	CORE_SHARE of a chunk's rocks stay on until its patch pops, so there is always
	something left to aim at.

	IT IS ALSO WHAT YOU CARRY. ToolService encases the model in your off hand with a
	chunk per REMAINING patch, so an item you half-cleaned and walked away from is half
	emerged in your hand. The lump in the ground (`lump`) is the one deliberate exception
	— it is always fully crusted, because grading it by the roll would leak a
	"needs no cleaning" modifier before the reveal is supposed to happen at all.

	RARITY IS THE ONE THING THE ROCK IS ALLOWED TO SAY. The detector already told the
	player what tier they are hauling and the banner repeats it, so hiding it here would
	be a lie the rest of the UI immediately contradicts. The slag is cast a little of the
	way toward the rarity colour and lit by one faint PointLight of it — a Legendary lump
	reads warm against the soil and a Scrap one reads like a stone, without either turning
	into a coloured toy. Everything else about the item — name, flavour, what it is worth,
	what it looks like — stays under the rock.

	STASH-AND-RESTORE, THE SAME DEAL ITEMGRIME MADE. `paint` re-derives from the size and
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

--- ROCKS. Roughly how many small rocks a whole crust is tiled from, shared out over
--- however many chunks it has. It used to be 3 big blocks and 6 flakes per chunk --
--- two to six boulders in all -- and the wash read as "hold the trigger on a lump until
--- it pops". A hundred-odd pebbles is a shell you can watch come apart under the
--- stream, and still a small number of parts for the one item on the tub.
local ROCK_BUDGET = 100

--- A dug lump in the field, a bag icon or an exhibit pedestal: fewer, bigger rocks,
--- because there can be a lot of those about and nobody is washing them.
local LUMP_ROCKS = 32

--- How big a rock is, against the square cell it was tiled into. Over 1 so they
--- OVERLAP: a shell of rocks exactly cell-sized has hairline gaps the item reads
--- through at every seam.
local ROCK_COVER_MIN = 1.3
local ROCK_COVER_MAX = 1.65

--- How thick a rock is through the shell, as a share of the cell.
local ROCK_THICK_MIN = 0.65
local ROCK_THICK_MAX = 1.05

--- How far a rock stands proud of the box surface, as a share of its thickness. Some
--- sit flush and some stick out, which is what turns a tiled box into a lumpy one.
local ROCK_PROUD_MAX = 0.35

--- How much the box corners and edges are pulled in toward a rounded shell. The items
--- under the rock are capsules, not crates, so the corners of their bounding box are
--- empty air -- and a crust with square corners reads as a crate.
local ROUNDING = 0.5

--- The share of a chunk's rocks that stay on until its patch pops. The rest break off
--- one by one across the soak. Never all of them: a chunk with nothing left on it
--- would have its last second of work land on something invisible.
local CORE_SHARE = 0.25

--- One in this many rocks is a wedge, for the broken angles.
local WEDGE_EVERY = 4

--- A thin object (a bottle cap is millimetres through) still has to grow a lump you
--- can point a hose at, so the body used for all of the above is never smaller than
--- this in any axis.
local MIN_BODY = 0.9

--- How small a rock gets before it breaks off. Not much: the rocks are small now and
--- coming off one by one IS the erosion, so shrinking hard on top of that just opens
--- see-through gaps across the whole chunk long before any of it has gone.
local SHRINK_FLOOR = 0.72

--- The stretch of the soak the rocks break off across: none at the very first touch
--- of water, all but the core by SHED_LAST, and the core goes at the pop.
local SHED_FIRST = 0.04
local SHED_LAST = 0.9

--- How see-through a fully soaked chunk goes on its way out. Wet slag, sloughing off.
local WET_FADE = 0.3

--- ...and how much darker. Wet rock is darker rock, and it is the only cue that
--- separates "I have soaked this one" from "I have not started" at a glance.
local WET_DARKEN = 0.35

local GLOW_NAME = "CrustGlow"
local SIZE_ATTR = "CrustSize"
local COLOR_ATTR = "CrustColor"
--- A rock's place in its chunk's default shedding order, used when nothing says where
--- the water is landing (a banked soak re-applied at the start of a session).
local ORDER_ATTR = "CrustOrder"
--- A rock's index inside its chunk. The client reports the one its water hit, and the
--- server breaks rocks off nearest that one first.
local ROCK_ATTR = "CrustRock"
--- Set true the moment a piece has come off. The client watches it to throw the
--- falling copy; the server keeps the (now invisible) part until `shed` sweeps up.
local SHED_ATTR = "CrustShed"
-- Flagged with SHED_ATTR when the piece went because its WHOLE chunk popped (`shed`).
local BURST_ATTR = "CrustBurst"
--- How eroded a piece is (1 dry, 0 about to pop) and whether it is past the stream's
--- potency. Written by the server (`erode`), eased and drawn by CrustController.
local LEVEL_ATTR = "CrustLevel"
local TOUGH_ATTR = "CrustTough"
--- Every crust part carries it, so CrustController can find them to watch.
local TAG = "ItemCrust"
--- How long a shed part hangs about, invisible, before the server destroys it: long
--- enough that every client has seen the SHED_ATTR change before the part is gone.
local SHED_LINGER = 1

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

local function slagPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	className: string?
): BasePart
	local part = Instance.new(className or "Part") :: BasePart
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
	part:AddTag(TAG)
	part.Parent = parent
	return part
end

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

--- Pull a point on the box toward a rounded shell. Face centres stay put; edges and
--- corners come in by up to ROUNDING of the way a superellipse would take them.
local function rounded(point: Vector3, half: Vector3): Vector3
	local n = point / half
	local norm4 = (n.X ^ 4 + n.Y ^ 4 + n.Z ^ 4) ^ 0.25
	if norm4 < 1e-3 then
		return point
	end
	return point * (1 - ROUNDING + ROUNDING / norm4)
end

type Site = { at: Vector3, normal: Vector3, cell: number, chunk: number }

--- The shared core: about `budget` rocks tiled over a box of `body` around `pivot`,
--- dealt out to `total` chunks by which chunk direction each one faces most. Only
--- chunks 1 to `count` are built: a held item with some patches already washed off
--- keeps the same layout as the full lump, with the cleaned sides simply bare.
local function buildChunks(
	parent: Instance,
	count: number,
	total: number,
	budget: number,
	pivot: CFrame,
	body: Vector3,
	accent: Color3,
	rng: Random
): ({ [number]: { BasePart } }, { [number]: Vector3 })
	local half = body * 0.5
	local area = 2 * (body.X * body.Y + body.Y * body.Z + body.Z * body.X)
	local step = math.sqrt(area / math.max(budget, 6))

	local dirs: { Vector3 } = {}
	for index = 1, total do
		dirs[index] = spiralDir(index, total)
	end

	-- Every site first, so the chunk deal below sees the whole shell. Each face of the
	-- box is cut into near-square cells about `step` across, one rock per cell.
	local sites: { Site } = {}
	for axis = 1, 3 do
		local normalAxis = AXES[axis]
		local uAxis = AXES[axis % 3 + 1]
		local vAxis = AXES[(axis + 1) % 3 + 1]
		local uSpan = body:Dot(uAxis)
		local vSpan = body:Dot(vAxis)
		local uCells = math.max(1, math.floor(uSpan / step + 0.5))
		local vCells = math.max(1, math.floor(vSpan / step + 0.5))
		local cell = math.sqrt((uSpan / uCells) * (vSpan / vCells))
		for _, side in { -1, 1 } do
			local normal = normalAxis * side
			for u = 1, uCells do
				for v = 1, vCells do
					local du = ((u - 0.5 + rng:NextNumber(-0.18, 0.18)) / uCells - 0.5) * uSpan
					local dv = ((v - 0.5 + rng:NextNumber(-0.18, 0.18)) / vCells - 0.5) * vSpan
					local at = rounded(normal * half:Dot(normalAxis) + uAxis * du + vAxis * dv, half)
					-- Which chunk owns this rock: the one whose direction it faces most,
					-- measured on the box-normalised point so a long item's ends are not
					-- all handed to whichever chunk points along its length.
					local facing = at / half
					facing = if facing.Magnitude > 1e-3 then facing.Unit else normal
					local best, bestDot = 1, -math.huge
					for index, dir in dirs do
						local dot = facing:Dot(dir)
						if dot > bestDot then
							best, bestDot = index, dot
						end
					end
					table.insert(sites, { at = at, normal = normal, cell = cell, chunk = best })
				end
			end
		end
	end

	local zones: { [number]: { BasePart } } = {}
	local sums: { [number]: Vector3 } = {}
	for index = 1, count do
		zones[index] = {}
		sums[index] = Vector3.zero
	end

	for _, site in sites do
		-- Every draw happens for every site, built or not, so a held item with chunks
		-- washed off grows the SAME rocks on the sides it still has.
		local thick = site.cell * rng:NextNumber(ROCK_THICK_MIN, ROCK_THICK_MAX)
		local size = Vector3.new(
			site.cell * rng:NextNumber(ROCK_COVER_MIN, ROCK_COVER_MAX),
			site.cell * rng:NextNumber(ROCK_COVER_MIN, ROCK_COVER_MAX),
			thick
		)
		local spot = site.at + site.normal * thick * rng:NextNumber(0, ROCK_PROUD_MAX)
		local up = if math.abs(site.normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
		-- Face-on to its side of the box, then tipped and turned so neighbours do not
		-- line up into tiles. Kept under 25 degrees of tip: more swings a rock's corner
		-- clean out of the shell it is supposed to be filling.
		local lay = CFrame.lookAt(spot, spot + site.normal, up)
			* CFrame.Angles(
				math.rad(rng:NextNumber(-22, 22)),
				math.rad(rng:NextNumber(-22, 22)),
				math.rad(rng:NextNumber(-35, 35))
			)
		local shade = rockShade(rng, accent)
		local wedge = rng:NextInteger(1, WEDGE_EVERY) == 1
		local order = rng:NextNumber()

		local zone = zones[site.chunk]
		if zone == nil then
			continue
		end
		local rock = #zone + 1
		local part = slagPart(
			`Crust{site.chunk}_{rock}`,
			size,
			pivot * lay,
			shade,
			parent,
			if wedge then "WedgePart" else "Part"
		)
		part:SetAttribute(ROCK_ATTR, rock)
		part:SetAttribute(ORDER_ATTR, order)
		table.insert(zone, part)
		sums[site.chunk] += site.at
	end

	local anchors: { [number]: Vector3 } = {}
	for index = 1, count do
		local zone = zones[index]
		-- A chunk the deal left empty (a tiny budget on a long item can do it) still
		-- needs something to aim at: one rock where its direction meets the box.
		if #zone == 0 then
			local dir = dirs[index]
			local at = dir / math.max(math.abs(dir.X) / half.X, math.abs(dir.Y) / half.Y, math.abs(dir.Z) / half.Z)
			local part = slagPart(
				`Crust{index}_1`,
				Vector3.one * step * ROCK_COVER_MAX,
				pivot * CFrame.new(at),
				rockShade(rng, accent),
				parent
			)
			part:SetAttribute(ROCK_ATTR, 1)
			part:SetAttribute(ORDER_ATTR, 0)
			table.insert(zone, part)
			sums[index] = at
		end
		-- The anchor sits a little inside the chunk's own rocks: the wash bay's weak
		-- point rays back toward it from outside, and the near-miss rounding measures
		-- from it.
		anchors[index] = (pivot * CFrame.new(sums[index] / #zone * 0.6)).Position
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
---
--- `options.total` is how many chunks the item started with, when that is more than
--- `count` (a held item partly washed): the shell is laid out for the full set and only
--- the first `count` chunks are built. `options.rocks` overrides ROCK_BUDGET.
function ItemCrust.encase(
	model: Model,
	count: number,
	rarityName: string?,
	seed: (string | number)?,
	options: { total: number?, rocks: number? }?
): ({ [number]: { BasePart } }, { [number]: Vector3 })
	local accent = if rarityName then Rarity.get(rarityName).color else NEUTRAL
	local pivot, size = model:GetBoundingBox()
	local body = Vector3.new(
		math.max(size.X, MIN_BODY),
		math.max(size.Y, MIN_BODY),
		math.max(size.Z, MIN_BODY)
	)

	local chunks = math.max(count, 1)
	local total = math.max(chunks, options and options.total or 0)
	-- The budget is for the WHOLE shell, so a part-washed lump has fewer rocks, not
	-- the same number crammed onto what is left.
	local budget = options and options.rocks or ROCK_BUDGET
	local zones, anchors = buildChunks(model, chunks, total, budget, pivot, body, accent, Random.new(seedOf(seed)))
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
	local zones = buildChunks(model, 4, 4, LUMP_ROCKS, CFrame.new(), body, accent, Random.new(seedOf(seed)))

	-- SOMETHING TO PIVOT AND WELD BY. ToolService welds every other part to the
	-- primary before it lets go of the anchor, and a model with no PrimaryPart makes
	-- that choice by whatever GetDescendants happens to return first.
	local first = zones[1] and zones[1][1]
	model.PrimaryPart = first or model:FindFirstChildWhichIsA("BasePart")
	glow(model, accent, body.X)
	return model
end

--- One piece comes off: invisible and out of the aim ray at once, flagged so every
--- client can throw a falling copy of it from wherever it stands on their screen (the
--- turntable spins client-side, so only the client knows that). NOT destroyed here --
--- a part that is gone before the flag replicates is a flake nobody sees fall.
local function shedOne(part: BasePart)
	part:SetAttribute(SHED_ATTR, true)
	part.Transparency = 1
	part.CanQuery = false
end

--- Erode one chunk. `level` is 1 for untouched slag and 0 for a chunk about to come
--- off; `tough` means it is harder than this liquid is rated for. It used to mean
--- "cannot shift it at all" and froze the chunk dry and full size -- the potency wall.
--- There is no wall now (Contamination.secondsFor grinds instead), so a tough chunk
--- erodes like any other, only slowly, and is drawn darker slate the whole way down so
--- the player can see which rock is the slow one.
---
--- THE SERVER SAYS HOW ERODED, THE CLIENT DRAWS IT. This used to write Size, Colour,
--- Transparency and Material straight onto the part, which replicated at the wash
--- tick's ten hertz: every chunk shrank in visible steps. Now it stamps the level (and
--- whether the rock is tough) as attributes, and CrustController eases each part
--- toward them every frame and draws the look with `paint`. Shedding stays here: when a
--- piece comes off is the server's call.
---
--- HOW MANY ROCKS ARE OFF follows the level; WHICH ones follows the water. `near` is
--- where the stream is landing on this chunk (the rock the client says it hit), and
--- the rocks closest to it go first, so the hole opens under the hose. With no `near`
--- -- a banked soak put back at the start of a session -- they go in the chunk's own
--- shuffled order.
function ItemCrust.erode(parts: { BasePart }, level: number, tough: boolean, near: Vector3?)
	local amount = math.clamp(level, 0, 1)
	local live: { BasePart } = {}
	for _, part in parts do
		if part.Parent and not part:GetAttribute(SHED_ATTR) then
			table.insert(live, part)
		end
	end

	local core = math.max(1, math.ceil(#parts * CORE_SHARE))
	local progress = math.clamp(((1 - amount) - SHED_FIRST) / (SHED_LAST - SHED_FIRST), 0, 1)
	local wanted = math.floor(progress * math.max(#parts - core, 0) + 1e-6)
	local toShed = math.min(wanted - (#parts - #live), #live - 1)

	if toShed > 0 then
		local rank: { [BasePart]: number } = {}
		for _, part in live do
			if near then
				rank[part] = (part.Position - near).Magnitude
			else
				local order = part:GetAttribute(ORDER_ATTR)
				rank[part] = if type(order) == "number" then order else 0
			end
		end
		table.sort(live, function(a, b)
			return rank[a] < rank[b]
		end)
		for index = 1, toShed do
			shedOne(live[index])
		end
		live = table.move(live, toShed + 1, #live, 1, {})
	end

	for _, part in live do
		part:SetAttribute(LEVEL_ATTR, amount)
		part:SetAttribute(TOUGH_ATTR, tough)
	end
end

--- Which rock of its chunk a crust part is, for the client to report what its water
--- hit. Nil for anything that is not crust.
function ItemCrust.rockOf(part: Instance): number?
	local rock = part:GetAttribute(ROCK_ATTR)
	return if type(rock) == "number" then rock else nil
end

--- The rock with this index in a chunk, or nil.
function ItemCrust.findRock(parts: { BasePart }, rock: number): BasePart?
	for _, part in parts do
		if part:GetAttribute(ROCK_ATTR) == rock then
			return part
		end
	end
	return nil
end

--- Draw one piece of crust at `level` (1 dry and whole, 0 about to come off). Client
--- side, every frame a part is moving (CrustController). It re-derives from the size
--- and colour stashed on the part the first time it was painted, never from what is on
--- it now, so painting a falling level each frame walks the chunk down smoothly
--- instead of compounding a shrink onto a shrink.
function ItemCrust.paint(part: BasePart, level: number, tough: boolean)
	local amount = math.clamp(level, 0, 1)
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

	local soaked = 1 - amount
	part.Size = baseSize * (SHRINK_FLOOR + (1 - SHRINK_FLOOR) * amount)
	part.Transparency = soaked * WET_FADE
	if tough then
		part.Color = baseColor:Lerp(Color3.new(0, 0, 0), 0.35 + soaked * WET_DARKEN * 0.65)
	else
		part.Color = baseColor:Lerp(Color3.new(0, 0, 0), soaked * WET_DARKEN)
	end
	local material = if tough then Enum.Material.Slate else Enum.Material.Rock
	if part.Material ~= material then
		part.Material = material
	end
end

--- That patch is gone: take its chunk off the item. There is nothing to restore and no
--- fade — the slag was ON the object, and the object underneath is the point.
function ItemCrust.strip(parts: { BasePart })
	for _, part in parts do
		part:Destroy()
	end
end

--- That patch is gone, in the wash bay: break every piece still on the chunk off at
--- once, so the core tumbles away the way its flakes did, and sweep the lot up once
--- every client has seen it go. `strip` stays the instant version, for a crust being
--- rebuilt rather than washed off.
function ItemCrust.shed(parts: { BasePart })
	for _, part in parts do
		if part.Parent and not part:GetAttribute(SHED_ATTR) then
			-- Set BEFORE the shed flag, so it has replicated by the time a client reacts
			-- to that: CrustController throws a burst piece harder than a lone flake.
			part:SetAttribute(BURST_ATTR, true)
			shedOne(part)
		end
	end
	task.delay(SHED_LINGER, function()
		for _, part in parts do
			if part.Parent then
				part:Destroy()
			end
		end
	end)
end

--- Is there still rock on this item? The crust's own light is the marker: `encase`
--- hangs it, `clear` takes it down at the wash reveal, and a held item with no
--- patches left is built without it. ItemFxController keeps every effect off
--- until this goes false, so the glow is part of the reveal and does not leak
--- through the slag.
function ItemCrust.isCrusted(root: Instance): boolean
	local own = root:FindFirstChild(GLOW_NAME, true)
	return own ~= nil and own:IsA("PointLight")
end

--- The name of the crust's light, for a caller that watches for it to go away.
ItemCrust.GLOW_NAME = GLOW_NAME

--- The tag on every crust part, and the attribute that flips when one comes off.
ItemCrust.TAG = TAG
ItemCrust.SHED_ATTR = SHED_ATTR
ItemCrust.BURST_ATTR = BURST_ATTR
ItemCrust.LEVEL_ATTR = LEVEL_ATTR
ItemCrust.TOUGH_ATTR = TOUGH_ATTR

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
