--!strict
--[[
	NukeSignatures.luau — one distinguishing prop per item, keyed by Items.DEFS id.

	feat/nuke-item-signatures: 68 items sharing 7 silhouettes read as repetitive.
	Full bespoke geometry per item was already tried in concept and rejected as too
	complex (nuke-arsenal-retheme). This is the compromise: every item still comes
	out of NukeBase's one shared capsule archetype at its tier's palette/size, and a
	signature here bolts on ONE small prop (and may recolour named parts the base
	already built -- "Barrel", "Nose", "NeckA", "NeckB", "FinN") so the result reads
	as that specific item, not just its rarity.

	Only items worth calling out this way need an entry -- a missing key is not an
	error, it just means that item is the plain tier archetype (ItemModels.create
	looks this table up and treats a miss as "no signature", the same graceful-
	degrade the model registry itself documents for an unmodelled item).

	Being built out incrementally (start with the most distinct/flavourful items,
	expand from there) rather than all 68 at once -- see nuke-item-signatures memory
	for the running list and the ones still plain.
]]

local NukeBase = require(script.Parent.NukeBase)
type SignatureContext = NukeBase.SignatureContext

local NukeSignatures: { [string]: (ctx: SignatureContext) -> () } = {}

-- "Squeaks. Glows a little. Definitely not real." -- a rubber bath duck wearing a
-- nuke's silhouette: duck-yellow plastic, a bill, two eyes. No fins to remove --
-- NukeCommon.finCount is already 0, so the base shape does half the joke for free.
NukeSignatures.radioactive_rubber_duck = function(ctx)
	local yellow = Color3.fromHex("FFD447")
	local barrel = ctx.model:FindFirstChild("Barrel") :: BasePart?
	local nose = ctx.model:FindFirstChild("Nose") :: BasePart?
	if barrel then
		barrel.Color = yellow
		barrel.Material = Enum.Material.SmoothPlastic
	end
	if nose then
		nose.Color = yellow
		nose.Material = Enum.Material.SmoothPlastic
	end

	local r = ctx.noseRadius
	local noseX = ctx.barrelHalf + r * 0.85

	ctx.part(
		"SigBill",
		Vector3.new(r * 0.55, r * 0.22, r * 0.8),
		CFrame.new(noseX - r * 0.1, r * 0.8, 0),
		Color3.fromHex("F2A93B"),
		Enum.Material.SmoothPlastic
	)

	for _, side in { 1, -1 } do
		local eye = ctx.part(
			`SigEye{side}`,
			Vector3.new(0.12, 0.12, 0.12) * ctx.scale,
			CFrame.new(noseX, r * 0.3, r * 0.55 * side),
			Color3.fromHex("1A1A1A"),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
		eye.CastShadow = false
	end
end

-- "Gold-plated. Somebody really wanted this one to shine." -- full gold plating
-- (not just the usual tier palette) plus a raised band the standard stripe/chrome
-- toggles don't already draw at this position, so it reads as an added flourish.
NukeSignatures.gold_ring = function(ctx)
	local gold = Color3.fromHex("F5C94D")
	for _, name in { "Barrel", "Nose", "NeckA", "NeckB" } do
		local p = ctx.model:FindFirstChild(name) :: BasePart?
		if p then
			p.Color = gold
			p.Material = Enum.Material.Metal
			p.Reflectance = 0.3
		end
	end

	ctx.ring("SigBand", ctx.barrelHalf * 0.15, 0.4 * ctx.scale, ctx.diameter + 0.14 * ctx.scale, Color3.fromHex("FFF3C4"), false)
end

-- "Catches light nobody else out here can see." -- a small faceted gem cluster
-- mounted right on the nose tip: four angled Wedge facets around a glassy crown.
NukeSignatures.diamond_brooch = function(ctx)
	local gemColor = Color3.fromHex("D6F3FF")
	local tipX = ctx.barrelHalf + ctx.noseRadius * 0.95
	local base = ctx.noseRadius * 0.5

	for index = 1, 4 do
		local angle = (index - 1) / 4 * math.pi * 2
		local cframe = CFrame.new(tipX, 0, 0)
			* CFrame.Angles(angle, 0, 0)
			* CFrame.new(0, base * 0.5, 0)
			* CFrame.Angles(0, 0, math.rad(35))
		local gem = ctx.part(
			`SigGem{index}`,
			Vector3.new(base * 0.5, base * 0.7, base * 0.35),
			cframe,
			gemColor,
			Enum.Material.Glass,
			Enum.PartType.Wedge
		)
		gem.Reflectance = 0.25
		gem.Transparency = 0.15
	end

	local crown = ctx.part(
		"SigGemCrown",
		Vector3.new(base * 0.4, base * 0.4, base * 0.4),
		CFrame.new(tipX + base * 0.3, 0, 0),
		gemColor,
		Enum.Material.Glass,
		Enum.PartType.Ball
	)
	crown.Reflectance = 0.3
	crown.Transparency = 0.1
end

-- "The whole reason there's a Belt and not something worse." -- exposed, glowing
-- control rods poking out past the nose, like the casing barely contains a core.
NukeSignatures.reactor_rod = function(ctx)
	local rodColor = Color3.fromHex("7CFFB2")
	local tipX = ctx.barrelHalf + ctx.noseRadius * 0.7
	local rodLength = ctx.noseRadius * 1.1

	local offsets = {
		Vector3.new(0, ctx.noseRadius * 0.35, 0),
		Vector3.new(0, -ctx.noseRadius * 0.2, ctx.noseRadius * 0.32),
		Vector3.new(0, -ctx.noseRadius * 0.2, -ctx.noseRadius * 0.32),
	}
	for index, offset in offsets do
		local rod = ctx.part(
			`SigRod{index}`,
			Vector3.new(rodLength, 0.12 * ctx.scale, 0.12 * ctx.scale),
			CFrame.new(tipX + rodLength / 2, offset.Y, offset.Z),
			rodColor,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		rod.CastShadow = false
	end

	ctx.ring("SigCoreRing", ctx.barrelHalf * 0.3, 0.16 * ctx.scale, ctx.diameter + 0.05 * ctx.scale, rodColor, true)
end

-- "Heavier than it looks. Nobody's brave enough to open it." -- the sole Anomaly,
-- already the biggest and most decorated tier; adds one more thing the others
-- don't have, a heavy dark containment band with rivets, right at barrel centre
-- (the one spot this tier's own stripe/chrome/glow/crown toggles leave bare).
NukeSignatures.unlabeled_cylinder = function(ctx)
	local darkBand = Color3.fromHex("1C1C1C")
	ctx.ring("SigContainmentBand", 0, 0.55 * ctx.scale, ctx.diameter + 0.16 * ctx.scale, darkBand, false)

	local rivetColor = Color3.fromHex("FFD700")
	local count = 8
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local cframe = CFrame.new(0, 0, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, ctx.diameter / 2 + 0.05 * ctx.scale, 0)
		ctx.part(`SigRivet{index}`, Vector3.new(0.14, 0.14, 0.14) * ctx.scale, cframe, rivetColor, Enum.Material.Metal, Enum.PartType.Ball)
	end
end

return NukeSignatures
