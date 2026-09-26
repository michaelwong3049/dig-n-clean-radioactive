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

	FROM TIER 3 IT SPARKLES, and the top rung changes shape. Asked to make the auras
	"more cooler after the 2nd one", the user picked the sparkle storm (star dust, then
	electrons shedding sparkles, then embers at the feet, then a glitter burst from the
	core) and, for tier 6, the double helix over the atom (`form`, HELIX).

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
	    A ViewportFrame draws no Beams, Trails or lights, so the card gets a model
	    built from parts instead, which AuraController animates (`ICON_TAG`).

	All geometry is in studs for a stock-sized character (HumanoidRootPart 2 tall) and
	is scaled by the caller.
]]

local CollectionService = game:GetService("CollectionService")

local AuraLook = {}

--- The sparkle storm (option 1 of the tier 3-6 upgrade round): layers of sparkles
--- that stack up the ladder, one new layer per rung from tier 3. Zero switches a
--- layer off.
export type Sparkle = {
	dust: number, -- twinkling star dust drifting round the aura, particles/sec
	shed: number, -- sparkles each electron sheds as it flies, particles/sec
	embers: number, -- embers rising off the ground at the feet, particles/sec
	burst: number, -- a glitter burst out of the core every BURST_SECONDS, particles
}

export type Look = {
	--- "atom": `rings` tilted rings round the chest. "helix": the top rung's own
	--- shape, two strands spiralling feet to head (see HELIX); `rings` is unused.
	form: "atom" | "helix",
	color: Color3,
	rings: number, -- 1..3
	electrons: number, -- per ring (per strand, for the helix)
	width: number, -- ring beam width, studs
	transparency: number, -- ring beam transparency
	speed: number, -- electron orbit, radians/sec (ring 1; outer rings run a little faster)
	core: boolean, -- a pulsing light in the chest
	sparkle: Sparkle,
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

local NO_SPARKLE: Sparkle = { dust = 0, shed = 0, embers = 0, burst = 0 }

--- Tiers 1-2 are plain rings. From tier 3 each rung adds a sparkle layer (dust, then
--- electrons shedding, then embers, then the core's burst), and the top rung swaps
--- the atom for the double helix, picked from a round of six tier-6 shapes.
AuraLook.TIERS = {
	{ form = "atom", color = Color3.fromRGB(214, 150, 104), rings = 1, electrons = 1, width = 0.10, transparency = 0.45, speed = 2.0, core = false, sparkle = NO_SPARKLE },
	{ form = "atom", color = Color3.fromRGB(80, 220, 255), rings = 1, electrons = 1, width = 0.13, transparency = 0.38, speed = 2.4, core = false, sparkle = NO_SPARKLE },
	{
		form = "atom", color = Color3.fromRGB(92, 140, 255), rings = 2, electrons = 1, width = 0.16, transparency = 0.31, speed = 2.8, core = false,
		sparkle = { dust = 8, shed = 0, embers = 0, burst = 0 },
	},
	{
		form = "atom", color = Color3.fromRGB(176, 110, 255), rings = 2, electrons = 1, width = 0.19, transparency = 0.24, speed = 3.2, core = true,
		sparkle = { dust = 10, shed = 6, embers = 0, burst = 0 },
	},
	{
		form = "atom", color = Color3.fromRGB(255, 96, 196), rings = 3, electrons = 1, width = 0.22, transparency = 0.17, speed = 3.6, core = true,
		sparkle = { dust = 12, shed = 8, embers = 14, burst = 0 },
	},
	{
		form = "helix", color = Color3.fromRGB(255, 208, 72), rings = 3, electrons = 3, width = 0.26, transparency = 0.1, speed = 4.0, core = true,
		sparkle = { dust = 16, shed = 10, embers = 22, burst = 40 },
	},
} :: { Look }

--- Seconds between the top rung's glitter bursts.
AuraLook.BURST_SECONDS = 2.1
--- Where the feet are, studs below the chest centre on a stock rig (HumanoidRootPart
--- centre 3 above the ground, the chest LIFT above that). The embers rise from here.
AuraLook.FEET = -3.3

--- The top rung's double helix, in studs round the chest centre on a stock rig: two
--- strands spiral from just off the ground to above the head, a halo floats over the
--- head and a ring lies at the feet. The whole shape turns about the vertical at
--- `spin`, and each strand's electrons race up it `climb` laps a second, wrapping back
--- to the bottom.
AuraLook.HELIX = {
	strands = 2,
	bottom = -3.1,
	top = 2.1,
	radius = 2.3,
	bulge = 0.25, -- the strands draw in by this much at mid-height
	twist = 1.25, -- radians of turn per stud of height
	spin = 1.6, -- radians/sec
	climb = 0.35, -- laps/sec
	haloY = 2.6,
	haloRadius = 0.95,
	footY = AuraLook.FEET,
	footRadius = 2.4,
}

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

--- The helix's own turn about the vertical at time `t`: the frame the strands, halo and
--- foot ring sit in (all of HELIX's geometry is fixed in it).
function AuraLook.helixFrame(t: number): CFrame
	return CFrame.Angles(0, t * AuraLook.HELIX.spin, 0)
end

--- Strand `strand`'s point `s` of the way up (0 bottom, 1 top), in the helix frame, and
--- its tangent (the derivative by s, so its length is the strand's speed there).
function AuraLook.helixPoint(strand: number, s: number): (Vector3, Vector3)
	local h = AuraLook.HELIX
	local height = h.top - h.bottom
	local y = h.bottom + s * height
	local r = h.radius - h.bulge * math.sin(math.pi * s)
	local dr = -h.bulge * math.pi * math.cos(math.pi * s)
	local a = y * h.twist + (strand - 1) * 2 * math.pi / h.strands
	local da = h.twist * height
	local c, sn = math.cos(a), math.sin(a)
	return Vector3.new(c * r, y, sn * r), Vector3.new(-sn * da * r + c * dr, height, c * da * r + sn * dr)
end

--- How far up its strand (0..1) electron `e` of `strand` is at time `t`. Evenly spaced
--- along each strand, the two strands a little out of step.
function AuraLook.helixProgress(look: Look, strand: number, e: number, t: number): number
	local s = t * AuraLook.HELIX.climb + (e - 1) / look.electrons + (strand - 1) * 0.17
	return s - math.floor(s)
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

--- Tag on every `icon()` model. AuraController animates the ones on screen: the
--- electrons orbit (`poseIcon`) and the card's camera circles the atom at PRECESS,
--- which reads exactly like the rings precessing without moving a hundred segments a
--- frame. A ViewportFrame redraws whenever anything in it moves, so only the electrons
--- and the camera ever do.
AuraLook.ICON_TAG = "AuraIcon"

--- Ring `ring`'s frame inside an icon: its tilt, and nothing else. The icon never
--- precesses itself; the camera circles it instead (see ICON_TAG).
local function iconRingFrame(ring: number): CFrame
	return CFrame.Angles(0, 0, AuraLook.TILTS[ring] or 0)
end

--- A model of tier `tier`'s atom for a ViewportFrame: a nucleus, each ring as a loop of
--- short Neon segments, and its electrons as balls (in an "Electrons" child, which is
--- all `poseIcon` moves). Built at the origin, tagged ICON_TAG, posed at a fixed time
--- so it reads the same wherever nothing animates it.
function AuraLook.icon(tier: number): Model
	local look = AuraLook.get(tier)
	local model = Instance.new("Model")
	model.Name = `Aura{tier}`
	model:SetAttribute("AuraIcon", tier)

	local r = AuraLook.RADIUS
	local thick = 0.06 + look.width * 0.6
	local electrons = Instance.new("Model")
	electrons.Name = "Electrons"
	electrons.Parent = model
	local function electron(ring: number, e: number)
		local ball = iconPart(electrons, "Electron", AuraLook.electronColor(look), Vector3.one * (0.36 + look.width), CFrame.identity, true)
		ball.Shape = Enum.PartType.Ball
		ball:SetAttribute("Ring", ring)
		ball:SetAttribute("Electron", e)
	end

	if look.form == "helix" then
		-- Each strand as a chain of short segments laid point to point, then the halo
		-- and the foot ring. No turn: the card's camera circles it (see ICON_TAG).
		local h = AuraLook.HELIX
		local steps = 48
		for strand = 1, h.strands do
			local previous = AuraLook.helixPoint(strand, 0)
			for step = 1, steps do
				local point = AuraLook.helixPoint(strand, step / steps)
				local span = point - previous
				iconPart(model, "Strand", look.color, Vector3.new(thick, thick, span.Magnitude + 0.02), CFrame.lookAt((point + previous) / 2, point), true)
				previous = point
			end
			for e = 1, look.electrons do
				electron(strand, e)
			end
		end
		for _, loop in { { h.haloY, h.haloRadius, 16 }, { h.footY, h.footRadius, 36 } } do
			local frames, length = AuraLook.segments(loop[2], loop[3])
			for _, segment in frames do
				iconPart(model, "Ring", look.color, Vector3.new(length, thick, thick), CFrame.new(0, loop[1], 0) * segment, true)
			end
		end
		local nucleus = iconPart(model, "Nucleus", look.color, Vector3.one * 1.1, CFrame.identity, true)
		nucleus.Shape = Enum.PartType.Ball
		model.PrimaryPart = nucleus
		AuraLook.poseIcon(model, 0.9)
		CollectionService:AddTag(model, AuraLook.ICON_TAG)
		return model
	end

	local segments, length = AuraLook.segments(r, 36)
	for ring = 1, look.rings do
		local frame = iconRingFrame(ring)
		for _, segment in segments do
			iconPart(model, "Ring", look.color, Vector3.new(length, thick, thick), frame * segment, true)
		end
		for e = 1, look.electrons do
			electron(ring, e)
		end
	end

	local nucleus = iconPart(model, "Nucleus", look.color, Vector3.one * (if look.core then 1.1 else 0.8), CFrame.identity, look.core)
	nucleus.Shape = Enum.PartType.Ball
	if not look.core then
		nucleus.Color = look.color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	model.PrimaryPart = nucleus

	AuraLook.poseIcon(model, 0.9)
	CollectionService:AddTag(model, AuraLook.ICON_TAG)
	return model
end

--- Put an `icon()` model's electrons where they are at time `t`, in the model's own
--- frame (its pivot is the nucleus at the origin).
function AuraLook.poseIcon(model: Model, t: number)
	local electrons = model:FindFirstChild("Electrons")
	local tier = model:GetAttribute("AuraIcon")
	if electrons == nil or type(tier) ~= "number" then
		return
	end
	local look = AuraLook.get(tier)
	local r = AuraLook.RADIUS
	local pivot = model:GetPivot()
	for _, ball in electrons:GetChildren() do
		local ring, e = ball:GetAttribute("Ring"), ball:GetAttribute("Electron")
		if ball:IsA("BasePart") and type(ring) == "number" and type(e) == "number" and look.form == "helix" then
			-- On a helix card "Ring" is the strand.
			ball.CFrame = pivot * CFrame.new((AuraLook.helixPoint(ring, AuraLook.helixProgress(look, ring, e, t))))
		elseif ball:IsA("BasePart") and type(ring) == "number" and type(e) == "number" then
			local u = AuraLook.electronAngle(look, ring, e, t)
			ball.CFrame = pivot * iconRingFrame(ring) * CFrame.new(math.cos(u) * r, 0, math.sin(u) * r)
		end
	end
end

return AuraLook
