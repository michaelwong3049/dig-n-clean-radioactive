--!strict
--[[
	NukeBase.luau — shared geometry for every diggable nuke variant.

	One archetype, reskinned by rarity (feat/nuke-arsenal-retheme): a capsule-shaped
	body with a rounded nose dome, a stepped tail taper, and optional fins. Every tier
	factory (NukeCommon.luau .. NukeAnomaly.luau) calls NukeBase.create with its own
	color palette, a `sizeScale`, and a small set of detail toggles -- fins, a warning
	stripe, a chrome collar, a glow seam, rainbow bands, sparkle studs, star studs, a
	spiked "crown" tip -- so the whole ladder from a dead Common dud up to a glowing
	cartoonish Anomaly comes out of ONE builder instead of a bespoke sculpt per item.

	feat/nuke-model-rework: the previous body/nose were `Enum.PartType.Ball` parts
	given a non-uniform Size (long on one axis, short on the other two) to fake an
	elongated torpedo shape. Roblox's `Ball` and `Cylinder` primitives don't support
	that -- they collapse to a uniform sphere/circle derived from one axis and
	silently ignore the others (raycast-confirmed during the Stage-4 ooze-pool work;
	see the roblox-cylinder-ball-no-ellipse note). The old body rendered as a small
	sphere nowhere near the size the fin/nose placement math assumed -- that mismatch
	was the entire "deformed, parts don't connect" bug. The fix below never asks a
	single primitive for a non-uniform cross-section:

	  * Barrel  - a Cylinder with EQUAL Y/Z (true circular cross-section); only its
	              length axis (unaffected by the bug) is what makes it elongated.
	  * Nose    - a Ball sized as a true sphere (all three axes equal, matching the
	              barrel's own diameter) centered exactly on the barrel's end face.
	              Same radius as the cylinder it caps means it is tangent to it by
	              construction -- flush with no gap and no hand-tuned overlap fudge.
	  * Neck    - two stepped Cylinders (each internally uniform) narrowing toward
	              the tail, so fins mount on a base narrower than the main barrel.

	Stands upright with the nose at +Y (top) and the tail (fins) at -Y (bottom, the
	seat it rests on). Callers own placement and move the complete Model with PivotTo.

	Every part below is authored on paper lying on its side -- nose at +X, tail at
	-X -- because that is the natural way to reason about a body's length, a ring's
	wrap, and fins spaced around a tube axis. UPRIGHT then rotates each one 90°
	about Z (+X -> +Y) as it's placed, standing the whole rigid assembly on its fins
	without changing a single Size or offset number below.

	`sizeScale` (per tier, in NukeDetail) is baked directly into every constant and
	offset below, NOT applied afterward with `model:ScaleTo` -- DigService's own
	weight-driven `model:ScaleTo(Weight.sizeScale(item.weight))` runs on this same
	model later, and ScaleTo is ABSOLUTE (Shops.luau documents the same gotcha): a
	second ScaleTo call would overwrite this one instead of stacking with it. Baking
	the rarity size into the authored geometry means the model's scale-1.0 bookkeeping
	already includes it, so the later weight-based scale multiplies on top correctly
	-- the same orthogonal-but-stacking relationship weight and rarity already have
	everywhere else (color, value, odds).
]]

local NukeBase = {}

-- Reference proportions at sizeScale == 1. About 1.85:1 length:diameter -- fatter
-- and chunkier than the old torpedo (was closer to 2.6:1) and closer to a stout
-- cartoon bomb silhouette.
local BASE_BODY_DIAMETER = 2.0
local BASE_BARREL_LENGTH = 2.0
local BASE_NECK_LENGTH = 0.7
local BASE_NECK_DIAMETER_A = 1.7
local BASE_NECK_DIAMETER_B = 1.25
local BASE_FIN_LENGTH = 0.6
local BASE_FIN_SPAN = 1.5
local BASE_FIN_THICK = 0.18
local FIN_FLARE = math.rad(14)

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

export type NukeDetail = {
	key: string,
	displayName: string,
	bodyColor: Color3,
	noseColor: Color3,
	finColor: Color3,
	finCount: number, -- 0, 3, or 4
	sizeScale: number?, -- rarity's size multiplier; baked into geometry, see header
	stripeColor: Color3?,
	chrome: boolean?,
	glowColor: Color3?,
	bandColors: { Color3 }?,
	sparkleColor: Color3?,
	starColor: Color3?,
	crownColor: Color3?,
	gallerySize: number?,
}

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = UPRIGHT * cframe
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

--- A ring around the body: a short cylinder sharing the body's own X-axis, so it
--- needs no extra rotation to wrap around it. EQUAL Y/Z always -- see header.
local function ring(model: Model, name: string, x: number, width: number, diameter: number, color: Color3, neon: boolean)
	local p = part(
		model,
		name,
		Vector3.new(width, diameter, diameter),
		CFrame.new(x, 0, 0),
		color,
		if neon then Enum.Material.Neon else Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	if neon then
		p.CastShadow = false
	end
end

--- A small 4-point starburst (two crossed flat slivers) stuck to the body surface.
local function star(model: Model, name: string, cframe: CFrame, color: Color3, scale: number)
	local a = part(model, name .. "A", Vector3.new(0.03, 0.32, 0.08) * scale, cframe, color, Enum.Material.Neon)
	a.CastShadow = false
	local b = part(model, name .. "B", Vector3.new(0.03, 0.08, 0.32) * scale, cframe, color, Enum.Material.Neon)
	b.CastShadow = false
end

function NukeBase.create(detail: NukeDetail): Model
	local model = Instance.new("Model")
	model.Name = detail.key
	-- Locked before the first non-identity part, same as every other item factory --
	-- otherwise Roblox inherits a child's orientation as the Model's pivot.
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", detail.key)
	model:SetAttribute("DisplayName", detail.displayName)
	model:SetAttribute("GallerySize", detail.gallerySize or 3.4)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(12), math.rad(18), math.rad(8)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(8), math.rad(-24), 0))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(10), math.rad(-28), 0))

	-- Glowing/banded tiers read better with a flatter plastic base than the dull
	-- tiers' brushed metal.
	local bodyMaterial = if detail.glowColor or detail.bandColors
		then Enum.Material.SmoothPlastic
		else Enum.Material.Metal

	local s = detail.sizeScale or 1
	local bodyDiameter = BASE_BODY_DIAMETER * s
	local barrelLength = BASE_BARREL_LENGTH * s
	local barrelHalf = barrelLength / 2
	local noseRadius = bodyDiameter / 2
	local neckLength = BASE_NECK_LENGTH * s
	local neckDiameterA = BASE_NECK_DIAMETER_A * s
	local neckDiameterB = BASE_NECK_DIAMETER_B * s
	local finLength = BASE_FIN_LENGTH * s
	local finSpan = BASE_FIN_SPAN * s
	local finThick = BASE_FIN_THICK * s

	-- The barrel: a true (equal Y/Z) cylinder, so it actually renders at its full
	-- length instead of collapsing to a sphere the way the old stretched Ball did.
	part(model, "Barrel", Vector3.new(barrelLength, bodyDiameter, bodyDiameter), CFrame.new(0, 0, 0), detail.bodyColor, bodyMaterial, Enum.PartType.Cylinder)

	-- The nose dome: a true sphere (all three axes equal) centered exactly on the
	-- barrel's +X end face. Its radius already equals the barrel's, so it is
	-- tangent to the barrel by construction -- no gap, no overlap to hand-tune.
	part(model, "Nose", Vector3.new(bodyDiameter, bodyDiameter, bodyDiameter), CFrame.new(barrelHalf, 0, 0), detail.noseColor, bodyMaterial, Enum.PartType.Ball)

	-- The tail neck: two stepped, uniform-diameter cylinders narrowing toward the
	-- fins, butted flush against the barrel and each other (same axis, flat caps
	-- meeting exactly since each position is derived from the previous part's size).
	part(model, "NeckA", Vector3.new(neckLength / 2, neckDiameterA, neckDiameterA), CFrame.new(-barrelHalf - neckLength / 4, 0, 0), detail.bodyColor, bodyMaterial, Enum.PartType.Cylinder)
	part(model, "NeckB", Vector3.new(neckLength / 2, neckDiameterB, neckDiameterB), CFrame.new(-barrelHalf - neckLength * 3 / 4, 0, 0), detail.bodyColor, bodyMaterial, Enum.PartType.Cylinder)

	local tailX = -barrelHalf - neckLength

	if detail.stripeColor then
		ring(model, "Stripe", -barrelHalf * 0.2, 0.35 * s, bodyDiameter + 0.06 * s, detail.stripeColor, false)
	end

	if detail.chrome then
		local collar = part(
			model,
			"ChromeCollar",
			Vector3.new(0.22 * s, bodyDiameter + 0.1 * s, bodyDiameter + 0.1 * s),
			CFrame.new(barrelHalf, 0, 0),
			Color3.fromHex("E7ECEF"),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		collar.Reflectance = 0.35
	end

	if detail.glowColor then
		ring(model, "GlowSeam", barrelHalf * 0.5, 0.18 * s, bodyDiameter + 0.05 * s, detail.glowColor, true)
	end

	if detail.bandColors then
		local spread = barrelLength * 0.85
		local count = #detail.bandColors
		for index, color in detail.bandColors do
			local x = -spread / 2 + (spread * (index - 1) / math.max(count - 1, 1))
			ring(model, `Band{index}`, x, 0.16 * s, bodyDiameter + 0.06 * s, color, true)
		end
	end

	-- Fins mount on the narrow neck, back edge flush with the very tail tip so
	-- nothing overhangs past the end of the model into empty space.
	if detail.finCount > 0 then
		local finMountX = tailX + finLength / 2
		local finRadialOffset = neckDiameterB / 2 + finSpan / 2 - 0.22 * s
		for index = 1, detail.finCount do
			local angle = (index - 1) / detail.finCount * math.pi * 2 + math.pi / 4
			local cframe = CFrame.new(finMountX, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, finRadialOffset, 0)
				* CFrame.Angles(0, 0, FIN_FLARE)
			part(model, `Fin{index}`, Vector3.new(finLength, finSpan, finThick), cframe, detail.finColor, Enum.Material.Metal)
		end
	end

	if detail.sparkleColor then
		local spots = {
			Vector3.new(barrelHalf * 0.7, bodyDiameter * 0.42, bodyDiameter * 0.2),
			Vector3.new(-barrelHalf * 0.3, -bodyDiameter * 0.3, bodyDiameter * 0.38),
			Vector3.new(barrelHalf + noseRadius * 0.7, bodyDiameter * 0.1, -bodyDiameter * 0.4),
			Vector3.new(-barrelHalf * 0.9, bodyDiameter * 0.35, -bodyDiameter * 0.22),
		}
		for index, offset in spots do
			local p = part(model, `Sparkle{index}`, Vector3.new(0.12, 0.12, 0.12) * s, CFrame.new(offset), detail.sparkleColor, Enum.Material.Neon, Enum.PartType.Ball)
			p.CastShadow = false
		end
	end

	if detail.starColor then
		local spots = {
			CFrame.new(barrelHalf * 0.6, bodyDiameter * 0.46, 0) * CFrame.Angles(0, 0, math.rad(15)),
			CFrame.new(-barrelHalf * 0.8, -bodyDiameter * 0.44, 0) * CFrame.Angles(0, 0, math.rad(-10)),
		}
		for index, cframe in spots do
			star(model, `Star{index}`, cframe, detail.starColor, s)
		end
	end

	if detail.crownColor then
		local crownX = barrelHalf + noseRadius * 0.75
		local crownRadial = noseRadius * 0.55
		for index = 1, 6 do
			local angle = (index - 1) / 6 * math.pi * 2
			local cframe = CFrame.new(crownX, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, crownRadial, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			local spike = part(model, `Spike{index}`, Vector3.new(0.35, 0.1, 0.1) * s, cframe, detail.crownColor, Enum.Material.Neon)
			spike.CastShadow = false
		end
	end

	return model
end

return NukeBase
