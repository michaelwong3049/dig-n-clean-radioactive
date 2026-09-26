--[[
	One-time Studio command-bar migration: Toxic Twilight's five magnets go in as the
	Magnet track's tiers 7-11 (Config/Gear.Magnet rows 7-11, `camp = "twilight"`), after
	the Singularity Coil:

	  T7 Lattice Magnet   T8 Solar Magnet   T9 Void Magnet
	  T10 Nebula Magnet   T11 Omega Magnet

	KEPT IN GIT ON PURPOSE, same as import-twilight-detectors.luau beside it:
	ReplicatedStorage.Assets is not Rojo-synced, so the only record of what was done to
	the place file is this script. Run it in EDIT mode (a Play-mode edit is thrown away on
	Stop). Then Save and Publish. The shop rack does not change until the Twilight camp is
	rebuilt (`require(game.ServerScriptService.Server.build.CampSite).rebuild()`).

	The sources are the user's Import 3D results in `Workspace.AuxScene`, named by the
	art pack's own numbering (`tier_6_lattice` .. `tier_10_omega`), which is NOT this
	game's tier number: the pack's tier 6 is our tier 7. Each is `tier_x > magnet_x >
	<group> > <part>_Node > MeshPart`, no welds, collidable, one texture.

	THE CONTRACT IS THE ONE T2-T6 ALREADY USE, read off the live Singularity Coil rather
	than invented:

	  * `T<n>` Model, PrimaryPart `Grip` (an invisible 0.56 cube), with attributes
	    TierName, HoldPart and HoldCFrame. HoldPart and HoldCFrame are COPIED from T6:
	    every magnet from the Salvage Magnet up shares one hold pose, and that only works
	    because they all share one orientation, which is the next point.
	  * In the Grip's frame the bend sits at the origin, the poles run along +Z and the
	    legs spread along +/-X, the thin side up (+Y). build/Shops' RACK_HANG.Magnet
	    (legs = +Z, face = +Y) poses the rack from exactly these axes. The imports stand
	    upright instead -- poles along +Y, legs along X, depth along Z -- so the Grip is
	    turned -90 degrees about X (its +Z onto world +Y), then the whole model is pivoted
	    so the Grip ends world-aligned like every other template.
	  * One sub-Model named after the tier (so ToolFX's recursive part lookups and the
	    "nested one level" note in ToolFX stay true), PrimaryPart `bend`, every other part
	    welded to `bend`, and the Grip welded to `bend` too.
	  * Massless, unanchored, CanCollide off: welded to a hand, a collidable part buried in
	    the ground shoves the whole character up (import-detector-models.luau's lesson).
	    CanQuery stays on for the meshes like T6's; CanTouch on for the Grip only.

	SIZE: ALL FIVE ARE ONE SIZE, on the user's call ("they should all be relatively the
	same size"). A first pass grew them up the ladder by leg spread, and the Lattice came
	out visibly smaller than the Omega. Each is now scaled so its box runs TARGET_LENGTH
	along the poles (Grip +Z), bend to pole tip; the Singularity Coil is 7.9 on the same
	measure. ToolService.HELD_TOOL_SCALE (0.75) still shrinks them in hand, to ~6 studs
	like the Singularity Coil. 10 was tried first and read far too big in the hand.

	Refuses to run twice: if T7 already exists it stops before changing anything, and it
	asserts every source is present and every part count adds up before it touches the
	live folder. The sources are cloned, never moved, so the imports stay in AuxScene as a
	safety net until someone cleans them out.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TIERS = {
	{ tier = 7, source = "tier_6_lattice", name = "Lattice Magnet" },
	{ tier = 8, source = "tier_7_solar", name = "Solar Magnet" },
	{ tier = 9, source = "tier_8_void", name = "Void Magnet" },
	{ tier = 10, source = "tier_9_nebula", name = "Nebula Magnet" },
	{ tier = 11, source = "tier_10_omega", name = "Omega Magnet" },
}

local TARGET_LENGTH = 8 -- studs along the poles (Grip +Z), every rung the same

local GRIP_SIZE = 0.56 -- T2-T6's Grip

local magnetFolder = ReplicatedStorage.Assets.Tools.Magnet
assert(magnetFolder:FindFirstChild("T7") == nil, "T7 already exists: this migration has already run")

local singularity = magnetFolder:FindFirstChild("T6")
assert(singularity and singularity:GetAttribute("TierName") == "Singularity Coil", "T6 is not the Singularity Coil; the ladder is not where this expects it")
local holdPart = singularity:GetAttribute("HoldPart")
local holdCFrame = singularity:GetAttribute("HoldCFrame")
assert(typeof(holdCFrame) == "CFrame", "T6 has no HoldCFrame to share")

local function partsOf(model: Instance): { BasePart }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function findAuxSource(name: string): Model?
	for _, aux in workspace:GetChildren() do
		if aux.Name == "AuxScene" then
			local m = aux:FindFirstChild(name)
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	return nil
end

-- Everything is built and checked on clones first; the live folder is touched last.
local built: { { tier: number, model: Model, parts: number, scale: number } } = {}

for _, spec in TIERS do
	local source = findAuxSource(spec.source)
	assert(source, `no {spec.source} under a Workspace.AuxScene to import`)
	local expected = #partsOf(source)

	local clone = source:Clone()

	-- Flatten: every mesh straight under one sub-Model named after the tier; the
	-- import's wrapper models (magnet_x, groups, *_Node) go.
	local work = Instance.new("Model")
	work.Name = "_work_T" .. spec.tier
	local body = Instance.new("Model")
	body.Name = spec.name
	body.Parent = work
	for _, part in partsOf(clone) do
		part.Parent = body
	end
	clone:Destroy()
	assert(#body:GetChildren() == expected, `{spec.name}: flatten kept {#body:GetChildren()} parts, expected {expected}`)

	local bend: BasePart? = nil
	local outerPole: BasePart? = nil
	for _, part in body:GetChildren() do
		if part.Name == "bend" then
			assert(bend == nil, `{spec.name}: more than one part named "bend"`)
			bend = part :: BasePart
		elseif part.Name == "pole_left" then
			outerPole = part :: BasePart
		end
	end
	assert(bend and outerPole, `{spec.name}: missing "bend" or "pole_left"`)
	body.PrimaryPart = bend

	-- The poles have to stand straight up from the bend for the -90 degree turn below to
	-- lay them along the Grip's +Z.
	local rise = outerPole.Position - bend.Position
	assert(rise.Y > 0.5 and math.abs(rise.Z) < 0.05, `{spec.name}: poles do not stand up from the bend (rise {rise})`)

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(GRIP_SIZE, GRIP_SIZE, GRIP_SIZE)
	grip.Transparency = 1
	grip.Material = Enum.Material.Plastic
	grip.CFrame = CFrame.new(bend.Position) * CFrame.Angles(-math.pi / 2, 0, 0)
	grip.Parent = work
	work.PrimaryPart = grip

	-- Grip world-aligned, like every other template (Shops and ToolService only ever
	-- read it relatively, but a template that sits identity is one less thing to doubt).
	work:PivotTo(CFrame.new(grip.Position))

	-- Scale about the Grip to the one shared length. The Grip is world-aligned now, so
	-- the bounding box's Z is the length along the poles.
	local _, boxSize = work:GetBoundingBox()
	work:ScaleTo(work:GetScale() * TARGET_LENGTH / boxSize.Z)

	local polesAt = grip.CFrame:PointToObjectSpace(outerPole.Position)
	assert(polesAt.Z > 1 and math.abs(polesAt.Y) < 0.05, `{spec.name}: poles are not along the Grip's +Z (at {polesAt})`)

	for _, part in partsOf(work) do
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		if part ~= grip then
			part.CanQuery = true
			part.CanTouch = true
		else
			part.CanQuery = false
			part.CanTouch = true
		end
		if part ~= bend then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bend
			weld.Part1 = part
			weld.Parent = if part == grip then grip else bend
		end
	end

	local final = #partsOf(work)
	assert(final == expected + 1, `{spec.name}: final part count {final}, expected {expected + 1} (parts + Grip)`)

	work:SetAttribute("TierName", spec.name)
	work:SetAttribute("HoldPart", holdPart)
	work:SetAttribute("HoldCFrame", holdCFrame)

	table.insert(built, { tier = spec.tier, model = work, parts = final, scale = work:GetScale() })
end

-- Only now touch the live ladder.
for _, b in built do
	b.model.Name = "T" .. b.tier
	b.model.Parent = magnetFolder
	print(`[migration] Magnet.T{b.tier} {b.model:GetAttribute("TierName")}: {b.parts} parts, {string.format("%.2f", b.scale)}x`)
end
