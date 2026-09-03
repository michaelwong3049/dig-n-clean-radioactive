--!strict
--[[
	Hose.luau — the cleaning track's seven nozzles, as geometry.

	WHY THIS IS CODE AND NOT ART. Every other gear track's tier models live in
	`Assets/Tools/<Track>/T<n>` inside the PLACE FILE, produced by a generator that was
	run from the command bar once and then lost (see Config/ToolTiers' header, and
	build/BaseCamp's). That leaves ToolTiers as a recipe with no cook: nothing at
	runtime reads a single column of it, the shop rack degrades to painted fallback
	blocks, and nobody can regenerate the art. This track opts out of that problem
	entirely — the hose is built from primitives, in git, on the same "models as code"
	footing as Shared/ItemModels.

	THE HOSE WAS ALREADY THE VERB. Before this file, the Cleaner track sold a Wire
	Brush and an Acid Sponge while the wash bay welded a fire hose into your hand and
	ToolService pulled the cleaner back OUT of it (you cannot hold a sponge and a
	nozzle in one fist). So the thing you bought was never the thing you cleaned with.
	Seven hoses collapses that: the tier you own IS the nozzle you aim.

	THE FRAME, and everything downstream depends on it:
	  * authored at the ORIGIN, so callers own placement and move the Model with PivotTo
	  * -Z is the business end. `CFrame.lookAt` puts its target on -Z, and WashController
	    aims the nozzle with exactly that, so this has to hold parked AND held or the
	    water leaves through the grip.
	  * the PrimaryPart is `Nozzle`: an INVISIBLE, AXIS-ALIGNED block. The visible tube
	    is a Cylinder, whose native axis is X and which must therefore be rotated to lie
	    along Z — and once it is rotated, every attachment offset on it would have to be
	    written in a twisted local frame. An unrotated anchor keeps `Muzzle` at a plain
	    (0, 0, -z) anyone can read, and gives the hand-weld and the aim Motor6D one
	    unambiguous frame to work in.
	  * `Muzzle` and `HoseEnd` attachments on that core are a CONTRACT, not a
	    convention: World.verify() fails the whole rebuild over a hose missing either.
	    Muzzle is where the water leaves, HoseEnd is where the reel's Beam runs to.

	ANCHORING IS ONE PROPERTY ON ONE PART. The shell welds to the core and is never
	anchored itself; parking the nozzle is `core.Anchored = true` and picking it up is
	`false` plus a weld to the hand. Anchoring one part of a welded assembly pins the
	whole assembly, so there is no state where half the nozzle gets left behind.

	SIZE IS CARRIED BY THE GEOMETRY, NOT BY ToolTiers' `scale`. That column exists
	because the Detector and Magnet tracks are ONE base model reused twenty-one times,
	so a multiplier is the only size knob they have. Seven authored silhouettes do not
	need a second one on top, and having both is how a tier ends up 8% off its own
	drawing for no reason. ToolTiers.Cleaner's scale column is therefore 1.00 all the
	way down, and this file reads that table for COLOUR only.

	TIER 2 IS THE STATION'S OWN HOSE. build/Plots.buildHoseRig parks a tier-2 nozzle on
	every plot's pump, so its proportions are held byte-identical to the hand-built one
	that lived inline in that file before this one existed. Only the two brass repair
	bands are new, and they are what makes "Patched Fire Hose" read as patched.

	WHICH IS WHY THE GRIP IS A DARKENED BODY AND NOT THE ACCENT. The hand-built nozzle
	painted its grip `Kit.C.hoseGreenDark` — a THIRD colour, and ToolTiers rows carry
	only two plus an optional glow. Reaching for `accent` instead turned the fire hose's
	grip brass, which is both wrong and the sort of drift a "byte-identical" claim is
	supposed to prevent. `SHADE` (below) derives it instead, so every tier gets a grip
	darker than its own body without a third column existing to be filled in wrong.
]]

-- Relative, like every other module under Shared: `script` is Shared/ToolModels/Hose,
-- so Parent.Parent is Shared. Reaching through ReplicatedStorage instead would hardcode
-- this file to one Rojo mount point.
local ToolTiers = require(script.Parent.Parent.Config.ToolTiers)

local Hose = {}

Hose.TRACK = "Cleaner"

--- The tier the plot's own parked nozzle is built at (build/Plots.buildHoseRig).
--- Named rather than inlined because WashService's fallback path — "this place has no
--- hose on the pump" — has to agree with it, and two loose 2s is how they drift.
Hose.STATION_TIER = 2

--- A Cylinder's native axis is its own local X. `yaw90` sends that X to -Z, which is
--- genuinely front-to-back. NB Kit.R.cylAlongZ is ang(90, 90, 0), which composes to
--- send X to +Y and stands the cylinder UP — its name is a lie and it is not what any
--- barrel here wants. See build/Plots' note at the old nozzle for the full story.
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

--- How much of the body colour a grip or a strap keeps. 0.65 was solved, not picked:
--- it is the factor that takes Kit.C.hoseGreen (47, 163, 106) closest to the
--- hoseGreenDark (28, 110, 71) the hand-built fire-hose grip used, landing within four
--- points per channel. Every other tier then gets the same relationship for free.
local SHADE = 0.65

local function shaded(c: Color3): Color3
	return Color3.new(c.R * SHADE, c.G * SHADE, c.B * SHADE)
end

type Tube = { len: number, dia: number, z: number }
type Extra = {
	name: string,
	size: Vector3,
	pos: Vector3,
	paint: string, -- "body" | "shade" | "accent" | "glow"
	shape: string?, -- "Cylinder" (default) | "Block"
	rot: CFrame?,
}
type Form = {
	barrel: Tube,
	grip: { size: Vector3, pos: Vector3 },
	collar: Tube?,
	taper: Tube?,
	tip: Tube?,
	muzzle: number,
	hoseEnd: number,
	accentMaterial: Enum.Material,
	extras: { Extra },
}

--- One row per Gear.Cleaner tier, in the same order, and the names in the comments
--- are that table's names. `barrel`/`grip` are the two pieces every hose has; the
--- rest of the silhouette is what separates a garden hose from a plasma lance.
---
--- WHAT THE LADDER IS SAYING, so nobody re-derives it: rubber, then canvas and brass,
--- then industrial steel, then a laboratory, then something that should not exist.
--- Same story the Detector and Magnet tracks tell in ToolTiers, told in silhouette
--- here because this track finally has silhouettes to tell it with.
local FORMS: { Form } = {
	-- 1  Garden Hose — a thin rubber tube with a plastic thumb lever. No brass, no
	-- collar, nothing machined. It is the free tier and it should look free.
	{
		barrel = { len = 1.30, dia = 0.46, z = 0.10 },
		grip = { size = Vector3.new(0.34, 0.78, 0.44), pos = Vector3.new(0, -0.46, 0.42) },
		collar = nil,
		taper = { len = 0.55, dia = 0.34, z = -0.78 },
		tip = { len = 0.20, dia = 0.44, z = -1.12 },
		muzzle = -1.28,
		hoseEnd = 1.00,
		accentMaterial = Enum.Material.SmoothPlastic,
		extras = {
			{ name = "ThumbLever", size = Vector3.new(0.18, 0.10, 0.44), pos = Vector3.new(0, 0.28, 0.30), paint = "accent", shape = "Block" },
		},
	},

	-- 2  Patched Fire Hose — the station's own nozzle. Stubby and fat on purpose: a
	-- cartoon prop is a few big shapes, and the slim finely stepped first version read
	-- as a technical drawing at arm's length and as nothing at all from thirteen studs.
	{
		barrel = { len = 1.60, dia = 0.92, z = 0.15 },
		grip = { size = Vector3.new(0.46, 1.00, 0.58), pos = Vector3.new(0, -0.60, 0.55) },
		collar = { len = 0.44, dia = 1.06, z = 1.00 },
		taper = { len = 0.90, dia = 0.68, z = -0.90 },
		tip = { len = 0.26, dia = 0.96, z = -1.42 },
		muzzle = -1.60,
		hoseEnd = 1.30,
		accentMaterial = Enum.Material.Metal,
		extras = {
			-- The patches. Brass repair clamps, deliberately at different diameters so
			-- they read as two separate fixes rather than as decorative banding.
			{ name = "PatchBandFore", size = Vector3.new(0.14, 0.99, 0.99), pos = Vector3.new(0, 0, -0.20), paint = "accent" },
			{ name = "PatchBandAft", size = Vector3.new(0.10, 0.96, 0.96), pos = Vector3.new(0, 0, 0.58), paint = "accent" },
		},
	},

	-- 3  Pressure Lance — the first industrial rung. The barrel stops being the whole
	-- object: a narrow steel lance runs out ahead of it, which is the silhouette that
	-- says "this is pressure, not volume". Gauge on top so the tier reads from above
	-- too, which is the angle the shop rack presents it at.
	{
		barrel = { len = 1.85, dia = 0.84, z = 0.25 },
		grip = { size = Vector3.new(0.50, 1.05, 0.60), pos = Vector3.new(0, -0.64, 0.72) },
		collar = { len = 0.42, dia = 0.98, z = 1.22 },
		taper = { len = 0.55, dia = 0.56, z = -0.72 },
		tip = { len = 0.22, dia = 0.46, z = -2.12 },
		muzzle = -2.28,
		hoseEnd = 1.50,
		accentMaterial = Enum.Material.Metal,
		extras = {
			{ name = "Lance", size = Vector3.new(1.40, 0.36, 0.36), pos = Vector3.new(0, 0, -1.35), paint = "accent" },
			{ name = "Gauge", size = Vector3.new(0.14, 0.42, 0.42), pos = Vector3.new(0, 0.52, 0.55), paint = "accent", rot = UPRIGHT },
		},
	},

	-- 4  Chem Injector — a canister strapped over the barrel and feeding into it. The
	-- one tier whose upgrade is legible as CARGO rather than as a bigger gun, which is
	-- what a chemical dose actually is.
	{
		barrel = { len = 1.90, dia = 0.92, z = 0.22 },
		grip = { size = Vector3.new(0.50, 1.08, 0.60), pos = Vector3.new(0, -0.66, 0.75) },
		collar = { len = 0.44, dia = 1.06, z = 1.24 },
		taper = { len = 0.80, dia = 0.70, z = -0.95 },
		tip = { len = 0.26, dia = 0.90, z = -1.48 },
		muzzle = -1.66,
		hoseEnd = 1.52,
		accentMaterial = Enum.Material.Metal,
		extras = {
			{ name = "Canister", size = Vector3.new(1.25, 0.62, 0.62), pos = Vector3.new(0, 0.74, 0.30), paint = "accent" },
			{ name = "CanisterCap", size = Vector3.new(0.14, 0.68, 0.68), pos = Vector3.new(0, 0.74, -0.36), paint = "body" },
			{ name = "FeedLine", size = Vector3.new(0.16, 0.52, 0.16), pos = Vector3.new(0, 0.36, -0.30), paint = "shade", shape = "Block" },
			{ name = "StrapFore", size = Vector3.new(0.74, 0.70, 0.14), pos = Vector3.new(0, 0.40, -0.02), paint = "shade", shape = "Block" },
			{ name = "StrapAft", size = Vector3.new(0.74, 0.70, 0.14), pos = Vector3.new(0, 0.40, 0.60), paint = "shade", shape = "Block" },
		},
	},

	-- 5  Ultrasonic Jet — no tip at all. The business end is an open emitter ring with
	-- a lit face inside it, flanked by two waveguide prongs. Nothing about it looks
	-- like it sprays, which is the point: this is the rung where the track stops being
	-- plumbing.
	{
		barrel = { len = 2.00, dia = 0.96, z = 0.25 },
		grip = { size = Vector3.new(0.52, 1.10, 0.62), pos = Vector3.new(0, -0.68, 0.78) },
		collar = { len = 0.44, dia = 1.08, z = 1.30 },
		taper = { len = 0.70, dia = 0.78, z = -0.95 },
		tip = nil,
		muzzle = -1.68,
		hoseEnd = 1.58,
		accentMaterial = Enum.Material.Metal,
		extras = {
			{ name = "EmitterRing", size = Vector3.new(0.28, 1.42, 1.42), pos = Vector3.new(0, 0, -1.45), paint = "accent" },
			{ name = "EmitterFace", size = Vector3.new(0.34, 0.92, 0.92), pos = Vector3.new(0, 0, -1.45), paint = "glow" },
			{ name = "ProngLeft", size = Vector3.new(0.90, 0.16, 0.16), pos = Vector3.new(-0.52, 0, -1.05), paint = "accent" },
			{ name = "ProngRight", size = Vector3.new(0.90, 0.16, 0.16), pos = Vector3.new(0.52, 0, -1.05), paint = "accent" },
		},
	},

	-- 6  Ion Cannon — a flared bell, stepped in three rings because a Cylinder cannot
	-- taper. Read face-on that is a cone; read from the side it is a horn. Either way
	-- it is the widest thing on the ladder, which is what buys the second-from-top rung
	-- its presence without adding length it has nowhere to put.
	{
		barrel = { len = 2.05, dia = 1.00, z = 0.30 },
		grip = { size = Vector3.new(0.54, 1.12, 0.64), pos = Vector3.new(0, -0.70, 0.80) },
		collar = { len = 0.46, dia = 1.12, z = 1.38 },
		taper = nil,
		tip = nil,
		muzzle = -1.82,
		hoseEnd = 1.66,
		accentMaterial = Enum.Material.Metal,
		extras = {
			{ name = "BellInner", size = Vector3.new(0.34, 1.16, 1.16), pos = Vector3.new(0, 0, -0.92), paint = "body" },
			{ name = "BellMid", size = Vector3.new(0.34, 1.44, 1.44), pos = Vector3.new(0, 0, -1.24), paint = "accent" },
			{ name = "BellOuter", size = Vector3.new(0.34, 1.70, 1.70), pos = Vector3.new(0, 0, -1.56), paint = "accent" },
			{ name = "BellMouth", size = Vector3.new(0.16, 1.50, 1.50), pos = Vector3.new(0, 0, -1.66), paint = "glow" },
		},
	},

	-- 7  Plasma Lance — the longest thing in the game you can hold, four radial heat
	-- fins where the barrel meets the lance, and a lit tip. It is the top rung and it
	-- is allowed to be absurd; what keeps it honest is that it still grips and still
	-- feeds from the same reel as the garden hose.
	{
		barrel = { len = 2.10, dia = 1.02, z = 0.32 },
		grip = { size = Vector3.new(0.56, 1.14, 0.66), pos = Vector3.new(0, -0.72, 0.84) },
		collar = { len = 0.46, dia = 1.14, z = 1.42 },
		taper = { len = 0.60, dia = 0.80, z = -0.90 },
		tip = { len = 0.24, dia = 0.52, z = -2.46 },
		muzzle = -2.62,
		hoseEnd = 1.70,
		accentMaterial = Enum.Material.Metal,
		extras = {
			{ name = "Lance", size = Vector3.new(1.55, 0.42, 0.42), pos = Vector3.new(0, 0, -1.60), paint = "accent" },
			{ name = "FinRight", size = Vector3.new(0.14, 0.66, 0.72), pos = Vector3.new(0.58, 0, -0.30), paint = "accent", shape = "Block" },
			{ name = "FinLeft", size = Vector3.new(0.14, 0.66, 0.72), pos = Vector3.new(-0.58, 0, -0.30), paint = "accent", shape = "Block" },
			{ name = "FinTop", size = Vector3.new(0.66, 0.14, 0.72), pos = Vector3.new(0, 0.58, -0.30), paint = "accent", shape = "Block" },
			{ name = "FinBottom", size = Vector3.new(0.66, 0.14, 0.72), pos = Vector3.new(0, -0.58, -0.30), paint = "accent", shape = "Block" },
		},
	},
}

--- How the nozzle sits in a hand, as a model attribute rather than a constant in the
--- three places that need it. `-Y` is down the arm on both rigs, so rotating the
--- nozzle's forward axis (`-Z`) onto it is what puts the business end pointing away
--- from the body rather than into the player's own elbow.
---
--- THE OFFSET IS SMALL ON PURPOSE. WashController pivots the nozzle about wherever
--- this puts it for the whole session, so it is not just the starting look — it is the
--- point the nozzle ORBITS. At -0.7 the muzzle dropped under the lip of the tub and
--- put the water into the rim a stud out of the nozzle.
Hose.HOLD = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local function tube(name: string, t: Tube, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(t.len, t.dia, t.dia)
	p.CFrame = CFrame.new(0, 0, t.z) * ALONG_Z
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Hose.count(): number
	return #FORMS
end

--- One nozzle, authored at the origin with its business end down -Z.
---
--- Clamped rather than asserted: a profile carrying a tier past the end of the ladder
--- (a rollback of Gear.Cleaner, say) must still hand the player something they can
--- clean with. Refusing to build is a softlock at the one station whose whole job is
--- to be the way out of one.
function Hose.create(tier: number): Model
	local index = math.clamp(math.floor(tier), 1, #FORMS)
	local form = FORMS[index]
	local look = ToolTiers.get(Hose.TRACK, index)

	local paints: { [string]: Color3 } = {
		body = look.body,
		-- What a hand closes around, and what straps a canister down: always darker
		-- than the thing it is fixed to, never the accent. See SHADE.
		shade = shaded(look.body),
		accent = look.accent,
		-- Falls back to the accent rather than to white: the bottom four tiers have no
		-- `glow`, and any part painted with it there is a lit face on an object that is
		-- not meant to have one.
		glow = look.glow or look.accent,
	}

	local model = Instance.new("Model")
	model.Name = "Hose"

	local core = Instance.new("Part")
	core.Name = "Nozzle"
	core.Size = Vector3.new(0.3, 0.3, 0.3)
	core.CFrame = CFrame.new()
	core.Transparency = 1
	core.Color = look.body
	core.Material = look.material
	core.Anchored = true
	core.Massless = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Parent = model

	local shell: { BasePart } = {}

	table.insert(shell, tube("NozzleBody", form.barrel, look.body, look.material))
	if form.collar then
		table.insert(shell, tube("NozzleCollar", form.collar, look.accent, form.accentMaterial))
	end
	if form.taper then
		table.insert(shell, tube("NozzleTaper", form.taper, look.accent, form.accentMaterial))
	end
	if form.tip then
		table.insert(shell, tube("NozzleTip", form.tip, paints.glow, form.accentMaterial))
	end

	local grip = Instance.new("Part")
	grip.Name = "NozzleGrip"
	grip.Size = form.grip.size
	grip.CFrame = CFrame.new(form.grip.pos)
	grip.Color = paints.shade
	grip.Material = look.material
	grip.Anchored = true
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	table.insert(shell, grip)

	for _, extra in form.extras do
		local p = Instance.new("Part")
		p.Name = extra.name
		p.Shape = if extra.shape == "Block" then Enum.PartType.Block else Enum.PartType.Cylinder
		p.Size = extra.size
		p.CFrame = CFrame.new(extra.pos) * (extra.rot or (if extra.shape == "Block" then CFrame.identity else ALONG_Z))
		p.Color = paints[extra.paint]
		p.Material = if extra.paint == "body" then look.material else form.accentMaterial
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		table.insert(shell, p)
	end

	-- Welded to the core, never anchored themselves — see the header. Parented after
	-- the weld exists so nothing spends a frame loose in the workspace.
	for _, part in shell do
		part.Anchored = false
		part.Massless = true
		part.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Name = "ShellWeld"
		weld.Part0 = core
		weld.Part1 = part
		weld.Parent = part
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(0, 0, form.muzzle)
	muzzle.Parent = core

	local hoseEnd = Instance.new("Attachment")
	hoseEnd.Name = "HoseEnd"
	hoseEnd.CFrame = CFrame.new(0, 0, form.hoseEnd)
	hoseEnd.Parent = core

	model.PrimaryPart = core
	model:SetAttribute("HoldCFrame", Hose.HOLD)
	model:SetAttribute("Tier", index)

	return model
end

return Hose
