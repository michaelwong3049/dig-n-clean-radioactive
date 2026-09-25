--!strict
--[[
	AuraLook.luau — what each Aura tier looks like: atom rings spinning round the chest.

	The Aura track (Config/Gear's Gear.Aura) replaced the hazmat Suit on request ("remove
	hazmat suits and replace them with an aura you wear to protect yourself from rads").
	Same four stats, same prices; only the name and the look changed. The look was
	picked from six animated mockups (style 5, "atom rings"): electron orbits round
	the chest, which reads as "nuclear" at a glance.

	THE LADDER IS READ OFF THE RINGS. One ring at tiers 1-2, two at 3-4, three at 5-6;
	a glowing core lights the chest from tier 4; the top tier doubles its electrons.
	Every rung is also brighter, wider and faster than the one below it, so two players
	on the same ring count still read apart, and the colour tells the rung by name.

	THE COLOURS STAY OFF THE HUD'S TWO RESERVED ONES. PLAN's one colour rule gives pure
	white to aura failure (UIKit.C.burn) and green to exposure (UIKit.C.green), so no
	rung may be either — a gold aura is fine, a white or green one would tell a player
	something false about their own health. Spec pins that.

	WHO USES THIS:
	  * client/Controllers/AuraController — draws every character's aura with Beams
	    (the rings) and small Neon balls with Trails (the electrons), and the aura on
	    the Outfitter's mannequin (`DISPLAY_TAG`).
	  * server/Services/AuraService — stamps `ATTRIBUTE` on each character.
	  * client/Controllers/StationController — `icon()` in the shop card's art well.
	    A ViewportFrame draws no Beams, Trails or lights, so the card gets a still model
	    built from parts instead.

	All geometry is in studs for a stock-sized character (HumanoidRootPart 2 tall) and
	is scaled by the caller.
]]

local AuraLook = {}

export type Look = {
	color: Color3,
	rings: number, -- 1..3
	electrons: number, -- per ring
	width: number, -- ring beam width, studs
	transparency: number, -- ring beam transparency
	speed: number, -- electron orbit, radians/sec (ring 1; outer rings run a little faster)
	core: boolean, -- a pulsing light in the chest
}

--- Character attribute AuraService writes: the equipped Aura tier.
AuraLook.ATTRIBUTE = "AuraTier"
--- A part carrying this tag gets an aura drawn round it too (the Outfitter's
--- mannequin). `AuraTier` on it picks the tier; `AuraCycle` = true walks the ladder.
AuraLook.DISPLAY_TAG = "AuraDisplay"
--- Seconds each tier shows for on a cycling display.
AuraLook.CYCLE_SECONDS = 3

--- Ring radius and how far above the HumanoidRootPart's centre the rings are centred.
AuraLook.RADIUS = 2.5
AuraLook.LIFT = 0.5
--- The rings' tilts about the character's forward axis: flat, then +/-60 degrees,
--- the classic atom. Ring 1 is the flat one, so a one-ring aura is a halo round the
--- waist rather than a sash.
AuraLook.TILTS = { 0, math.rad(60), math.rad(-60) }
--- The whole atom turns slowly about the vertical, radians/sec, so the tilted rings
--- sweep round the body instead of hanging still.
AuraLook.PRECESS = 0.45

AuraLook.TIERS = {
	{ color = Color3.fromRGB(214, 150, 104), rings = 1, electrons = 1, width = 0.10, transparency = 0.45, speed = 2.0, core = false },
	{ color = Color3.fromRGB(80, 220, 255), rings = 1, electrons = 1, width = 0.13, transparency = 0.38, speed = 2.4, core = false },
	{ color = Color3.fromRGB(92, 140, 255), rings = 2, electrons = 1, width = 0.16, transparency = 0.31, speed = 2.8, core = false },
	{ color = Color3.fromRGB(176, 110, 255), rings = 2, electrons = 1, width = 0.19, transparency = 0.24, speed = 3.2, core = true },
	{ color = Color3.fromRGB(255, 96, 196), rings = 3, electrons = 1, width = 0.22, transparency = 0.17, speed = 3.6, core = true },
	{ color = Color3.fromRGB(255, 208, 72), rings = 3, electrons = 2, width = 0.26, transparency = 0.1, speed = 4.0, core = true },
} :: { Look }

function AuraLook.count(): number
	return #AuraLook.TIERS
end

function AuraLook.get(tier: number): Look
	return AuraLook.TIERS[math.clamp(math.floor(tier), 1, #AuraLook.TIERS)]
end

--- The electron's own colour: the tier's, a quarter of the way to white, so it reads
--- as the hot point riding the ring without turning into the burn's white.
function AuraLook.electronColor(look: Look): Color3
	return look.color:Lerp(Color3.new(1, 1, 1), 0.25)
end

--- Ring `ring`'s frame relative to the chest centre at time `t`. The ring lies in the
--- frame's XZ plane (its axis is the frame's Y).
function AuraLook.ringFrame(ring: number, t: number): CFrame
	local tilt = AuraLook.TILTS[ring] or 0
	local wobble = 0.06 * math.sin(t * 0.8 + ring * 2)
	return CFrame.Angles(0, t * AuraLook.PRECESS, 0) * CFrame.Angles(0, 0, tilt + wobble)
end

--- Where along ring `ring` electron `e` is at time `t`, radians.
function AuraLook.electronAngle(look: Look, ring: number, e: number, t: number): number
	return t * (look.speed + 0.45 * (ring - 1)) + ring * 2.1 + (e - 1) * (2 * math.pi / look.electrons)
end

--- A point on ring `ring` at angle `u`, relative to the chest centre.
function AuraLook.ringPoint(ring: number, u: number, t: number, radius: number): Vector3
	return AuraLook.ringFrame(ring, t) * Vector3.new(math.cos(u) * radius, 0, math.sin(u) * radius)
end

--- A ring of `count` straight segments at `radius`, for building one out of parts: each
--- segment's CFrame in the ring's own frame (its X along the ring), and the length that
--- closes the loop. Used by `icon` and by the Outfitter's roof atom (build/ShopThemes).
function AuraLook.segments(radius: number, count: number): ({ CFrame }, number)
	local step = 2 * math.pi / count
	local frames = table.create(count)
	for s = 0, count - 1 do
		local u = (s + 0.5) * step
		-- The tangent at u is (-sin u, 0, cos u): the ring's own X turned -(u + 90
		-- degrees) about its Y.
		table.insert(frames, CFrame.new(math.cos(u) * radius, 0, math.sin(u) * radius) * CFrame.Angles(0, -u - math.pi / 2, 0))
	end
	return frames, 2 * radius * math.sin(step / 2) + 0.02
end

local function iconPart(model: Model, name: string, color: Color3, size: Vector3, cf: CFrame, neon: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	part.CFrame = cf
	part.Parent = model
	return part
end

--- A still model of tier `tier`'s atom, for a ViewportFrame: a nucleus, each ring as a
--- loop of short Neon segments, and its electrons as balls. Built at the origin. The
--- snapshot time is fixed so every card shows the same pose.
function AuraLook.icon(tier: number): Model
	local look = AuraLook.get(tier)
	local model = Instance.new("Model")
	model.Name = `Aura{tier}`

	local r = AuraLook.RADIUS
	local t = 0.9
	local thick = 0.06 + look.width * 0.6
	local segments, length = AuraLook.segments(r, 36)
	for ring = 1, look.rings do
		local frame = AuraLook.ringFrame(ring, t)
		for _, segment in segments do
			iconPart(model, "Ring", look.color, Vector3.new(length, thick, thick), frame * segment, true)
		end
		for e = 1, look.electrons do
			local u = AuraLook.electronAngle(look, ring, e, t)
			local at = AuraLook.ringPoint(ring, u, t, r)
			iconPart(model, "Electron", AuraLook.electronColor(look), Vector3.one * (0.36 + look.width), CFrame.new(at), true)
		end
	end

	local nucleus = iconPart(model, "Nucleus", look.color, Vector3.one * (if look.core then 1.1 else 0.8), CFrame.identity, look.core)
	nucleus.Shape = Enum.PartType.Ball
	if not look.core then
		nucleus.Color = look.color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	for _, part in model:GetChildren() do
		if part:IsA("Part") and part.Name == "Electron" then
			part.Shape = Enum.PartType.Ball
		end
	end
	model.PrimaryPart = nucleus
	return model
end

return AuraLook
