--!strict
--[[
	NukeBase.luau — shared geometry for every diggable nuke variant.

	One archetype, reskinned by rarity (feat/nuke-arsenal-retheme): a torpedo-shaped
	body with a nose cap and optional tail fins. Every tier factory (NukeCommon.luau
	.. NukeAnomaly.luau) calls NukeBase.create with its own color palette and a small
	set of detail toggles -- fins, a warning stripe, a chrome collar, a glow seam,
	rainbow bands, sparkle studs, star studs, a spiked "crown" tip -- so the whole
	ladder from a dead Common dud up to a glowing cartoonish Anomaly comes out of ONE
	builder instead of a bespoke sculpt per item. Bounding-box-checked in Studio at
	roughly 4-5.6 studs tall, 1.7-2.8 studs across -- Config/Weight's `sizeScale` and
	`auraScale` do the actual per-item resizing on top of this base proportion.

	Stands upright with the nose at +Y (top) and the tail (fins) at -Y (bottom, the
	seat it rests on). Callers own placement and move the complete Model with PivotTo.

	Every part below is authored on paper lying on its side -- nose at +X, tail at
	-X -- because that is the natural way to reason about a body's length, a ring's
	wrap, and fins spaced around a tube axis. UPRIGHT then rotates each one 90°
	about Z (+X -> +Y) as it's placed, standing the whole rigid assembly on its fins
	without changing a single Size or offset number below.
]]

local NukeBase = {}

local BODY_LENGTH = 4.4
local BODY_DIAMETER = 1.7
local NOSE_LENGTH = 1.1
local FIN_LENGTH = 1.0
local FIN_SPAN = 0.95
local FIN_THICK = 0.12

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

export type NukeDetail = {
	key: string,
	displayName: string,
	bodyColor: Color3,
	noseColor: Color3,
	finColor: Color3,
	finCount: number, -- 0, 3, or 4
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
--- needs no extra rotation to wrap around it.
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
local function star(model: Model, name: string, cframe: CFrame, color: Color3)
	local a = part(model, name .. "A", Vector3.new(0.03, 0.32, 0.08), cframe, color, Enum.Material.Neon)
	a.CastShadow = false
	local b = part(model, name .. "B", Vector3.new(0.03, 0.08, 0.32), cframe, color, Enum.Material.Neon)
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

	part(model, "Body", Vector3.new(BODY_LENGTH, BODY_DIAMETER, BODY_DIAMETER), CFrame.new(0, 0, 0), detail.bodyColor, bodyMaterial, Enum.PartType.Ball)

	-- Sunk 0.4 stud back from the body's own tip (not perched just beyond it): two
	-- Ball parts only blend into one silhouette where they actually overlap, and
	-- both ellipsoids taper toward zero radius at their poles, so anything short of
	-- a real bite out of the body's tapered tip renders as two spheres with a gap
	-- between them, live-checked in Studio.
	part(
		model,
		"Nose",
		Vector3.new(NOSE_LENGTH, BODY_DIAMETER * 0.72, BODY_DIAMETER * 0.72),
		CFrame.new(BODY_LENGTH / 2 - 0.4, 0, 0),
		detail.noseColor,
		bodyMaterial,
		Enum.PartType.Ball
	)

	if detail.stripeColor then
		ring(model, "Stripe", -0.4, 0.35, BODY_DIAMETER + 0.06, detail.stripeColor, false)
	end

	if detail.chrome then
		local collar = part(
			model,
			"ChromeCollar",
			Vector3.new(0.22, BODY_DIAMETER + 0.1, BODY_DIAMETER + 0.1),
			CFrame.new(BODY_LENGTH / 2 - 0.3, 0, 0),
			Color3.fromHex("E7ECEF"),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		collar.Reflectance = 0.35
	end

	if detail.glowColor then
		ring(model, "GlowSeam", 0.6, 0.18, BODY_DIAMETER + 0.05, detail.glowColor, true)
	end

	if detail.bandColors then
		local spread = BODY_LENGTH * 0.6
		local count = #detail.bandColors
		for index, color in detail.bandColors do
			local x = -spread / 2 + (spread * (index - 1) / math.max(count - 1, 1))
			ring(model, `Band{index}`, x, 0.16, BODY_DIAMETER + 0.06, color, true)
		end
	end

	if detail.finCount > 0 then
		local tailX = -BODY_LENGTH / 2 + 0.15
		for index = 1, detail.finCount do
			local angle = (index - 1) / detail.finCount * math.pi * 2 + math.pi / 4
			local cframe = CFrame.new(tailX, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, BODY_DIAMETER / 2 + FIN_SPAN / 2 - 0.15, 0)
			part(model, `Fin{index}`, Vector3.new(FIN_LENGTH, FIN_SPAN, FIN_THICK), cframe, detail.finColor, Enum.Material.Metal)
		end
	end

	if detail.sparkleColor then
		local spots = {
			Vector3.new(0.6, BODY_DIAMETER * 0.42, BODY_DIAMETER * 0.2),
			Vector3.new(-0.3, -BODY_DIAMETER * 0.3, BODY_DIAMETER * 0.38),
			Vector3.new(1.2, BODY_DIAMETER * 0.1, -BODY_DIAMETER * 0.4),
			Vector3.new(-1.1, BODY_DIAMETER * 0.35, -BODY_DIAMETER * 0.22),
		}
		for index, offset in spots do
			local p = part(model, `Sparkle{index}`, Vector3.new(0.12, 0.12, 0.12), CFrame.new(offset), detail.sparkleColor, Enum.Material.Neon, Enum.PartType.Ball)
			p.CastShadow = false
		end
	end

	if detail.starColor then
		local spots = {
			CFrame.new(0.4, BODY_DIAMETER * 0.46, 0) * CFrame.Angles(0, 0, math.rad(15)),
			CFrame.new(-1.0, -BODY_DIAMETER * 0.44, 0) * CFrame.Angles(0, 0, math.rad(-10)),
		}
		for index, cframe in spots do
			star(model, `Star{index}`, cframe, detail.starColor)
		end
	end

	if detail.crownColor then
		local noseX = BODY_LENGTH / 2 + NOSE_LENGTH * 0.5
		for index = 1, 6 do
			local angle = (index - 1) / 6 * math.pi * 2
			local cframe = CFrame.new(noseX, 0, 0)
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, BODY_DIAMETER * 0.3, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			local spike = part(model, `Spike{index}`, Vector3.new(0.35, 0.1, 0.1), cframe, detail.crownColor, Enum.Material.Neon)
			spike.CastShadow = false
		end
	end

	return model
end

return NukeBase
