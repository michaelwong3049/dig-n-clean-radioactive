--[[
	RadFx.luau — what the dose looks like from inside the helmet.

	THIS REPLACES FOUR RECTANGLES. HudController used to tint the screen with four
	gradient bands, one per edge. They were honest placeholder work, but the corners
	gave them away: four bands overlapping draw a box, and a box on your screen reads
	as UI. Nothing about it said "this is taking you apart" — it said "an element is
	fading in". The escalation PLAN §3.1 asks for is FELT, and a rectangle is not a
	feeling.

	Everything here is Frames, UICorner, UIStroke and UIGradient — no image assets, so
	every layer re-tints per state. PLAN §14's ONE COLOUR RULE still holds and this
	file is the strictest place in the client about it: exposure damage is GREEN, suit
	failure is WHITE, and the two never blend into a third thing. The cracks layer is
	white BECAUSE it only ever appears while the suit is failing. Blood is the third
	colour and it answers to HEALTH, never to rads — see the BLOOD constant.

	NINE LAYERS, EACH ARRIVING AT ITS OWN THRESHOLD, so escalation is a sequence
	rather than one slider being dragged. Eight of them answer to the rad meter, your
	health, or your suit. The ninth answers to WHERE YOU ARE, and it is the loudest
	thing in the file — see `over` on update():

	  iris    elliptical rings closing in from beyond the frame. This is the vignette's
	          replacement — round, and moving. Vision tunnelling, not a border.
	  burns   soft blotches that bloom at the edge of sight and creep inward, one at a
	          time as the meter climbs. Tissue going, not a gradient ramping.
	  grain   single sparks. Particles landing on the back of your eye — the picture
	          half of the click bed GeigerController is already playing. Two banks: one
	          on the meter, one the LIGHT grade owns outright (LIGHT_GRAIN_COUNT).
	  tear    horizontal signal breakup past DANGER. The feed failing, not the eye.
	  cracks  fractures spidering in from the frame's edges, WHITE and dark-outlined so
	          they read against a bright sky, and only while the suit is failing. This
	          is the layer that means destroyed.
	  bleed   a red rim at the very edge of the glass, driven by health.
	  splats  blood hitting the inside of the visor and running down it. The drips only
	          grow while you are actually losing health, which is what separates them
	          from a decal.
	  throb   a heartbeat over the whole picture, faster as the meter fills.
	  veil    the blind layer, and the only one allowed to touch the middle of the
	          screen. Lit by nothing except standing in air your suit is not rated for:
	          the iris slams down to a keyhole, the tunnel goes dark, the blur goes to
	          24, and the answer to "can I sneak one dig in down here" becomes no.

	OVER-TIER COMES IN THREE GRADES, NOT ONE SLIDER. `over` used to drive every
	over-tier layer linearly, which meant its two ends said the same sentence at two
	volumes: a toe over the line was a faint darkening, and deep in the wrong stage
	was total. Neither read as a distinct STATE. It is now split at LIGHT_SPAN into
	two channels that do different jobs (see update()).

	THE FAILURE RAMP IS GRADED BY THE SAME NUMBER, and that matters more than the
	split does. `failing` is a boolean, so ramping `st.fail` to a flat 1 on it used to
	fire every crack, the 5-stud blur, the blood and the camera shove the moment you
	stepped one foot past your rating — which is what "it jumps from nothing to
	everything" actually was. See FAIL_FLOOR and `failTarget`. Grading the `over`
	layers alone cannot fix it, because that whole block sits UNDER them.

	  LIGHT     `light`, peaking at ~1.7x your rating and fading back out as blind
	            arrives. The picture BREAKS UP — a second bank of static all its own,
	            the feed tearing, colour draining, the throb quickening — but the
	            middle of the screen is never touched and this grade adds only 2.5 to
	            the blur (measured live: 3.2 total in Stage 1 at 1.35x rating, against
	            29.9 at the intense end — and 24 of 80 cracks lit, against all 80).
	            You can still read the ground. This is a warning you can work through,
	            and it is the grade a player meets by stepping one stage past their
	            suit, which used to be a barely-visible darkening.
	  REGULAR   the low half of `blind`. The tunnel starts closing and the blur
	            becomes real. Working is possible; it is no longer comfortable.
	  INTENSE   `blind` at full, ~3x your rating. Untouched to the digit — `light` is
	            back at zero by then, so every layer reduces to exactly its old form:
	            the veil, the keyhole, the 24 blur, the sentence.

	Plus a colour-correction and blur pass on Lighting. Those instances are created by
	the CLIENT, so they are this player's sight going — not the world's weather. That
	is the whole reason exposure can be a personal, per-player state and still be felt
	across the entire screen.

	COST: ~269 frames, built once, and the container is Visible = false below
	EXPOSURE_WARN — which is most of the time anyone is actually playing. Nothing in
	here allocates per frame.
]]

local Lighting = game:GetService("Lighting")

local UIKit = require(script.Parent.UIKit)

local RadFx = {}

local GREEN = UIKit.C.green
local WHITE = UIKit.C.burn
-- The burn blotches sit UNDER the iris tint, so they need to be darker than the
-- meter green or they read as glowing lights rather than as dead tissue. Same hue,
-- so the one-colour rule survives: it is still exposure's green, just necrotic.
local ROT = GREEN:Lerp(Color3.new(0, 0, 0), 0.58)
-- What blindness is made of. Not pure black: the tunnel keeps a breath of the field's
-- green in it, so losing your sight still looks like the air did it to you.
local VOID = GREEN:Lerp(Color3.new(0, 0, 0), 0.9)
-- BLOOD IS THE ONE COLOUR IN HERE THAT IS NOT ON THE EXPOSURE LADDER, and it is
-- deliberately not driven by exposure either: it rides on HEALTH. Green is the dose,
-- white is the suit, red is you — three states that never say the same thing, which
-- is why a third colour does not break PLAN §14's rule. Blood driven by RADS would
-- break it, because then red would only be repeating what the green already said.
local BLOOD = Color3.fromRGB(122, 10, 14)
local BLOOD_DARK = Color3.fromRGB(58, 4, 6)

-- Seeded, so the damage pattern is identical every session. A blotch layout that
-- reshuffles on respawn reads as randomness; one that persists reads as YOUR helmet.
local rng = Random.new(0x2A0D)

-- WHERE THE LIGHT GRADE ENDS AND SIGHT STARTS GOING, on HudController's `over`
-- ramp (0 = rated for this air, 1 = three times your tolerance). 0.22 is ~1.7x your
-- rating, comfortably past the 1.1x-1.4x a player lands on by walking one stage too
-- deep — so the entrance to a stage you are not rated for is entirely light, and
-- pushing east into it is what starts closing the tunnel.
local LIGHT_SPAN = 0.22
-- HOW BROKEN THE SUIT READS AT THE INSTANT IT STARTS FAILING. `failing` is binary, so
-- something has to stand in for "barely" — this is the bottom of the failure ramp,
-- with `over` carrying it the rest of the way to 1. High enough that the glass agrees
-- with the countdown when it says SUIT FAILING, low enough that a toe over the line
-- is a few fractures rather than the whole visor.
local FAIL_FLOOR = 0.25

local RING_COUNT = 12
local BLEED_RING_COUNT = 5
local SPLAT_COUNT = 11
local BURN_COUNT = 14
local GRAIN_COUNT = 30
-- A SECOND BANK OF SPARKS THAT ONLY THE LIGHT GRADE LIGHTS. Turning grainChance up
-- for `light` would have bought nothing: over-tier always sets `failing`, `failing`
-- already puts that chance near 1, and a probability that is already 1 cannot make
-- more static out of thirty frames. Volume is the only dial left, so the light grade
-- gets its own thirty-four on top — enough that a screen one stage past your rating
-- is visibly noisier than the same screen at a pegged meter, which is the whole read.
local LIGHT_GRAIN_COUNT = 34
local TEAR_COUNT = 3

local ui = {}
local rings, burns, grains, tears, cracks, impacts = {}, {}, {}, {}, {}, {}
local splats, bleedRings = {}, {}
local st = { t = 0, fail = 0, run = 0, over = 0, live = false, built = false }

-- Every pixel measurement in this file is quoted against a 720-tall viewport and
-- scaled at layout time. Damage that is a fixed number of pixels wide swallows a
-- small window and disappears on a big one — the one thing an effect this loud
-- cannot be allowed to do is depend on how the player sized their screen.
local px = 1

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	-- Studio reports a zero viewport for a frame or two on load; dividing by that
	-- puts every crack at NaN and they never come back.
	if size.X < 1 or size.Y < 1 then
		return Vector2.new(1280, 720)
	end
	return size
end

-- ── Build ───────────────────────────────────────────────────────────

--- The iris. An ellipse's UIStroke draws OUTWARD from its border, so an oval
--- inscribed in the screen leaves the middle untouched and paints the corners —
--- which is exactly a vignette, minus the corners that made the old one a box.
--- Twelve of them at graduated radii stack into a falloff no single frame can fake.
local function buildIris(parent: Instance)
	for i = 1, RING_COUNT do
		local t = (i - 1) / (RING_COUNT - 1) -- 0 outermost, 1 innermost

		local ring = Instance.new("Frame")
		ring.Name = string.format("Ring%02d", i)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.ZIndex = 2
		ring.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring

		local stroke = Instance.new("UIStroke")
		stroke.Color = GREEN
		stroke.Transparency = 1
		stroke.Parent = ring

		rings[i] = {
			frame = ring,
			stroke = stroke,
			-- Outer rings carry the weight; inner ones only light up once the dose is
			-- serious, which is what makes the iris look like it is CLOSING. The span
			-- floor is deliberate: the middle of the screen is where the game is, and
			-- no dose short of the blackout is allowed to take it.
			span = 1.06 - t * 0.34,
			weight = (1 - t) ^ 1.7,
			reach = t, -- how deep the meter must be before this ring lights at all
		}
	end
end

--- One blotch: a soft halo with a denser core, both ellipses, both smeared by a
--- gradient at their own angle. Two overlapping soft ovals never look like an oval.
local function buildBurns(parent: Instance)
	for i = 1, BURN_COUNT do
		-- Placed around an ellipse, biased outward: damage arrives at the edge of
		-- vision first and eats inward, the same direction the iris is travelling.
		local angle = rng:NextNumber() * math.pi * 2
		local reach = 0.40 + rng:NextNumber() * 0.16
		local width = 70 + rng:NextNumber() * 110

		local halo = Instance.new("Frame")
		halo.Name = string.format("Burn%02d", i)
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.BackgroundColor3 = ROT
		halo.BackgroundTransparency = 1
		halo.BorderSizePixel = 0
		halo.Visible = false
		halo.ZIndex = 1
		halo.Parent = parent

		local haloCorner = Instance.new("UICorner")
		haloCorner.CornerRadius = UDim.new(0.5, 0)
		haloCorner.Parent = halo

		local haloGradient = Instance.new("UIGradient")
		haloGradient.Rotation = rng:NextNumber() * 360
		haloGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		haloGradient.Parent = halo

		local core = Instance.new("Frame")
		core.Name = "Core"
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * 0.2, 0.5 + (rng:NextNumber() - 0.5) * 0.2)
		core.Size = UDim2.fromScale(0.55, 0.62)
		core.BackgroundColor3 = ROT
		core.BackgroundTransparency = 1
		core.BorderSizePixel = 0
		core.ZIndex = 1
		core.Parent = halo

		local coreCorner = Instance.new("UICorner")
		coreCorner.CornerRadius = UDim.new(0.5, 0)
		coreCorner.Parent = core

		local coreGradient = Instance.new("UIGradient")
		coreGradient.Rotation = rng:NextNumber() * 360
		coreGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		coreGradient.Parent = core

		burns[i] = {
			halo = halo,
			core = core,
			u = 0.5 + math.cos(angle) * reach * 1.5,
			v = 0.5 + math.sin(angle) * reach,
			w = width,
			h = width * (0.55 + rng:NextNumber() * 0.5),
			-- Staggered thresholds. The blotches do not fade up together; they arrive
			-- one at a time, so the player can watch the damage SPREAD.
			at = (i - 1) / BURN_COUNT * 0.82,
			phase = rng:NextNumber() * 6.28,
			speed = 0.5 + rng:NextNumber() * 1.1,
		}
	end
end

--- Sparks. Each one lives for a few frames at a random spot and dies. At full dose
--- there are enough of them to read as a snowstorm on the inside of the visor.
local function buildGrain(parent: Instance)
	for i = 1, GRAIN_COUNT + LIGHT_GRAIN_COUNT do
		local dot = Instance.new("Frame")
		dot.Name = string.format("Grain%02d", i)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(2, 2)
		dot.BackgroundColor3 = GREEN
		dot.BackgroundTransparency = 1
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.ZIndex = 4
		dot.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot

		grains[i] = { frame = dot, life = 0, span = 0.1, lightOnly = i > GRAIN_COUNT }
	end
end

--- Signal breakup: a streak that fades out at both ends, so it is a tear in the
--- picture rather than a bar drawn over it.
local function buildTear(parent: Instance)
	for i = 1, TEAR_COUNT do
		local bar = Instance.new("Frame")
		bar.Name = string.format("Tear%d", i)
		bar.Size = UDim2.new(1, 0, 0, 8)
		bar.BackgroundColor3 = GREEN
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel = 0
		bar.Visible = false
		bar.ZIndex = 3
		bar.Parent = parent

		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = bar

		tears[i] = { frame = bar, life = 0, span = 0.1 }
	end
end

--- The rim. Blood pooling against the very edge of the frame, tight enough that it
--- never encroaches on the iris — this is on the glass, the green is in the air.
local function buildBleedRings(parent: Instance)
	for i = 1, BLEED_RING_COUNT do
		local t = (i - 1) / (BLEED_RING_COUNT - 1)

		local ring = Instance.new("Frame")
		ring.Name = string.format("Bleed%d", i)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1.1 - t * 0.16, 1.1 - t * 0.16)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.ZIndex = 3
		ring.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring

		local stroke = Instance.new("UIStroke")
		stroke.Color = BLOOD
		stroke.Transparency = 1
		stroke.Parent = ring

		bleedRings[i] = { stroke = stroke, weight = (1 - t) ^ 1.3 }
	end
end

--- Splatter on the inside of the visor: a soft smear, a dark centre, and a drip that
--- grows downward once the splat has landed. Splats are pinned to an EDGE rather than
--- scattered, because blood in the middle of your view is a blood texture, and blood
--- running down from the rim is your own.
local function buildSplats(parent: Instance)
	for i = 1, SPLAT_COUNT do
		local edge = i % 4
		local along = 0.08 + rng:NextNumber() * 0.84
		local u, v
		if edge == 0 then
			u, v = along, 0.03 + rng:NextNumber() * 0.08
		elseif edge == 1 then
			u, v = along, 0.9 + rng:NextNumber() * 0.08
		elseif edge == 2 then
			u, v = 0.02 + rng:NextNumber() * 0.09, along
		else
			u, v = 0.9 + rng:NextNumber() * 0.08, along
		end

		local width = 80 + rng:NextNumber() * 120

		local smear = Instance.new("Frame")
		smear.Name = string.format("Splat%02d", i)
		smear.AnchorPoint = Vector2.new(0.5, 0.5)
		smear.Position = UDim2.fromScale(u, v)
		-- Rotated, because eleven axis-aligned ovals is a pattern and blood is not.
		smear.Rotation = rng:NextNumber() * 360
		smear.BackgroundColor3 = BLOOD
		smear.BackgroundTransparency = 1
		smear.BorderSizePixel = 0
		smear.Visible = false
		smear.ZIndex = 3
		smear.Parent = parent

		local smearCorner = Instance.new("UICorner")
		smearCorner.CornerRadius = UDim.new(0.5, 0)
		smearCorner.Parent = smear

		local smearGradient = Instance.new("UIGradient")
		smearGradient.Rotation = rng:NextNumber() * 360
		smearGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		smearGradient.Parent = smear

		local clot = Instance.new("Frame")
		clot.Name = "Clot"
		clot.AnchorPoint = Vector2.new(0.5, 0.5)
		clot.Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * 0.24, 0.5 + (rng:NextNumber() - 0.5) * 0.24)
		clot.Size = UDim2.fromScale(0.5, 0.55)
		clot.BackgroundColor3 = BLOOD_DARK
		clot.BackgroundTransparency = 1
		clot.BorderSizePixel = 0
		clot.ZIndex = 3
		clot.Parent = smear

		local clotCorner = Instance.new("UICorner")
		clotCorner.CornerRadius = UDim.new(0.5, 0)
		clotCorner.Parent = clot

		local clotGradient = Instance.new("UIGradient")
		clotGradient.Rotation = rng:NextNumber() * 360
		clotGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.75),
		})
		clotGradient.Parent = clot

		-- Spatter. THIS is the difference between blood and a red circle: a hit throws
		-- droplets past its own edge, and three of them at unequal sizes break the
		-- silhouette that a single ellipse can never escape.
		local flecks = {}
		for f = 1, 3 do
			local fleck = Instance.new("Frame")
			fleck.Name = string.format("Fleck%d", f)
			fleck.AnchorPoint = Vector2.new(0.5, 0.5)
			fleck.Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * 1.5, 0.5 + (rng:NextNumber() - 0.5) * 1.5)
			fleck.Size = UDim2.fromScale(0.1 + rng:NextNumber() * 0.22, 0.1 + rng:NextNumber() * 0.2)
			fleck.BackgroundColor3 = if f == 1 then BLOOD_DARK else BLOOD
			fleck.BackgroundTransparency = 1
			fleck.BorderSizePixel = 0
			fleck.ZIndex = 3
			fleck.Parent = smear

			local fleckCorner = Instance.new("UICorner")
			fleckCorner.CornerRadius = UDim.new(0.5, 0)
			fleckCorner.Parent = fleck

			flecks[f] = fleck
		end

		-- The drip hangs off the splat and only ever gets LONGER while you are still
		-- bleeding. It is the one thing in this file that keeps moving after the state
		-- stops changing, which is exactly why it reads as a wound and not a decal.
		--
		-- IT IS A SIBLING OF THE SPLAT, NOT A CHILD, and that is the whole trick: the
		-- splat is randomly rotated so eleven of them do not line up, and a drip
		-- parented to it inherits that rotation and runs sideways. Blood runs DOWN.
		local drip = Instance.new("Frame")
		drip.Name = string.format("Drip%02d", i)
		drip.AnchorPoint = Vector2.new(0.5, 0)
		drip.Position = UDim2.fromScale(u + (rng:NextNumber() - 0.5) * 0.03, v)
		drip.Size = UDim2.fromOffset(0, 0)
		drip.BackgroundColor3 = BLOOD_DARK
		drip.BackgroundTransparency = 1
		drip.BorderSizePixel = 0
		drip.ZIndex = 3
		drip.Visible = false
		drip.Parent = parent

		local dripCorner = Instance.new("UICorner")
		dripCorner.CornerRadius = UDim.new(0.5, 0)
		dripCorner.Parent = drip

		splats[i] = {
			smear = smear,
			clot = clot,
			drip = drip,
			flecks = flecks,
			w = width,
			h = width * (0.38 + rng:NextNumber() * 0.32),
			dripWidth = 4 + rng:NextNumber() * 6,
			dripMax = 60 + rng:NextNumber() * 160,
			run = 0,
			-- Staggered like the burns: you do not get sprayed all at once, you get
			-- hit, and then hit again.
			at = (i - 1) / SPLAT_COUNT * 0.7,
			phase = rng:NextNumber() * 6.28,
		}
	end
end

--- Cracks are walked in NORMALISED space (0..1 on both axes) and converted to pixels
--- at layout time. That is why a window resize only stretches the fracture pattern
--- instead of leaving it hanging in mid-screen, and it is also why the recipe is
--- generated exactly once — a crack that redraws itself is a scratch on your visor
--- that heals, which is the opposite of the point.
---
--- THEY RUN ALONG THE EDGE, NOT AT THE MIDDLE. A crack aimed straight at screen
--- centre ends up drawn across the thing you are trying to dig, and the first read
--- is "line on my screen" rather than "my visor is going". Aimed inward at a shallow
--- angle and kept short, the same lines stay in the outer third with the rest of the
--- damage and the centre survives — which is exactly the deal the iris makes too.
local function buildCracks(parent: Instance)
	local starts = {
		Vector2.new(0.01, 0.16), Vector2.new(0.99, 0.22), Vector2.new(0.08, 0.97),
		Vector2.new(0.92, 0.94), Vector2.new(0.38, 0.01), Vector2.new(0.99, 0.68),
		Vector2.new(0.01, 0.74), Vector2.new(0.62, 0.99),
	}

	for index, start in starts do
		-- Inward, then swung well off centre so the run rakes across the corner it
		-- started in instead of driving for the middle.
		local aim = math.atan2(0.5 - start.Y, 0.5 - start.X)
			+ (if index % 2 == 0 then 0.95 else -0.95)
		local order = (index - 1) / #starts

		local impact = Instance.new("Frame")
		impact.Name = string.format("Impact%d", index)
		impact.AnchorPoint = Vector2.new(0.5, 0.5)
		impact.Position = UDim2.fromScale(start.X, start.Y)
		impact.BackgroundColor3 = WHITE
		impact.BackgroundTransparency = 1
		impact.BorderSizePixel = 0
		impact.Visible = false
		impact.ZIndex = 5
		impact.Parent = parent

		local impactCorner = Instance.new("UICorner")
		impactCorner.CornerRadius = UDim.new(0.5, 0)
		impactCorner.Parent = impact

		local impactGradient = Instance.new("UIGradient")
		impactGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		impactGradient.Parent = impact
		table.insert(impacts, { frame = impact, at = order * 0.5 })

		--- One run of segments outward from `from`, each starting where the last
		--- ended. Returns the point it reached so a fork can be hung off it.
		local function walk(from: Vector2, heading: number, count: number, scale: number, thin: boolean): Vector2
			local at = from
			local angle = heading
			for step = 1, count do
				-- Half the jitter the first pass used. A crack wanders; it does not
				-- zigzag, and zigzag is what made the first attempt read as rain.
				angle += (rng:NextNumber() - 0.5) * 0.45
				local len = (0.025 + rng:NextNumber() * 0.05) * scale
				local to = at + Vector2.new(math.cos(angle), math.sin(angle)) * len

				local seg = Instance.new("Frame")
				seg.Name = string.format("Crack%d_%d", index, step)
				seg.AnchorPoint = Vector2.new(0, 0.5)
				seg.BackgroundColor3 = WHITE
				seg.BackgroundTransparency = 1
				seg.BorderSizePixel = 0
				seg.Visible = false
				seg.ZIndex = 5
				seg.Parent = parent

				-- A white hairline over a bright sky is nearly nothing; the same line
				-- with a dark edge on it reads at any brightness. One stroke per
				-- segment is cheaper than drawing every crack twice.
				local outline = Instance.new("UIStroke")
				outline.Color = Color3.fromRGB(9, 11, 8)
				outline.Transparency = 1
				outline.Parent = seg

				table.insert(cracks, {
					frame = seg,
					outline = outline,
					from = at,
					to = to,
					thickness = if thin then 2 else 3.5,
					-- Segments nearer the origin surface first, so each crack GROWS
					-- outward from its impact instead of blinking in whole.
					at = order * 0.4 + (step / count) * 0.5,
				})

				at = to
			end
			return at
		end

		-- Trunk, a fork off its midpoint, and a second fork off its end: three lines
		-- meeting at angles is the smallest thing the eye reads as broken glass.
		local half = walk(start, aim, 3, 1, false)
		walk(half, aim + 0.7, 3, 0.75, true)
		local far = walk(half, aim - 0.35, 2, 0.9, false)
		walk(far, aim - 1.1, 2, 0.7, true)
	end
end

--- Pixel layout: the scale factor, the ring thickness that rides on it, and the
--- crack segments. Re-run whenever the viewport changes.
local function layout()
	local size = viewport()
	px = size.Y / 720

	for _, ring in rings do
		-- Thick enough that consecutive rings overlap (no banding), thin enough that
		-- the innermost one still stops well short of the middle. Blindness swells it
		-- further at drive time — see update().
		ring.thickness = 90 * px
		ring.stroke.Thickness = ring.thickness
	end

	for _, ring in bleedRings do
		ring.stroke.Thickness = 55 * px
	end

	for _, crack in cracks do
		crack.outline.Thickness = math.max(1, px)
	end

	for _, impact in impacts do
		impact.frame.Size = UDim2.fromOffset(150 * px, 110 * px)
	end

	for _, crack in cracks do
		local from = Vector2.new(crack.from.X * size.X, crack.from.Y * size.Y)
		local to = Vector2.new(crack.to.X * size.X, crack.to.Y * size.Y)
		local delta = to - from
		crack.frame.Position = UDim2.fromOffset(from.X, from.Y)
		crack.frame.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), math.max(1, math.round(crack.thickness * px)))
		crack.frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end
end

function RadFx.build(parent: Instance)
	if st.built then
		return
	end

	local root = Instance.new("Frame")
	root.Name = "Damage"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Visible = false
	root.ZIndex = 2
	root.Parent = parent
	ui.root = root

	buildBurns(root)
	buildIris(root)
	buildTear(root)
	buildBleedRings(root)
	buildSplats(root)
	buildGrain(root)
	-- The veil, built BEFORE the cracks so the fractures stay readable on top of it.
	-- This is the only layer allowed to darken the middle of the screen, and it is
	-- capped well short of opaque: blinding a player is the point, blacking them out
	-- is EXPOSURE_CAP's job and it has its own curtain to do it with.
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = VOID
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.ZIndex = 4
	veil.Parent = root
	ui.veil = veil

	buildCracks(root)
	layout()

	-- The throb. Full-screen and the topmost damage layer, because a heartbeat you
	-- can only see through the other layers is not a heartbeat.
	local throb = Instance.new("Frame")
	throb.Name = "Throb"
	throb.Size = UDim2.fromScale(1, 1)
	throb.BackgroundColor3 = GREEN
	throb.BackgroundTransparency = 1
	throb.BorderSizePixel = 0
	throb.ZIndex = 6
	throb.Parent = root
	ui.throb = throb

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	ui.colour = Instance.new("ColorCorrectionEffect")
	ui.colour.Name = "RadFxColour"
	ui.colour.Enabled = false
	ui.colour.Parent = Lighting

	ui.blur = Instance.new("BlurEffect")
	ui.blur.Name = "RadFxBlur"
	ui.blur.Size = 0
	ui.blur.Enabled = false
	ui.blur.Parent = Lighting

	st.built = true
end

-- ── Drive ───────────────────────────────────────────────────────────

local function sleep()
	if not st.live then
		return
	end
	st.live = false
	ui.root.Visible = false
	ui.colour.Enabled = false
	ui.blur.Enabled = false
end

--- `intensity` is HudController's own 0..1 escalation ramp (0 below EXPOSURE_WARN),
--- `failing` is the suit-failure flag, `healthFrac` is 0..1 of max HP, and `over` is
--- 0..1 of "how far past your suit's rating this air is" — 0 anywhere you are rated
--- for, 1 in a stage that should never have let you in. Nothing else belongs here.
function RadFx.update(dt: number, intensity: number, failing: boolean, healthFrac: number, over: number)
	if not st.built then
		return
	end

	st.t += dt

	-- Eased, not snapped, and it lifts faster than it lands: walking one step across
	-- a stage boundary must not strobe the whole screen, but a player who turns and
	-- runs has to be able to SEE that retreating is working, immediately. Resolved
	-- FIRST because the failure ramp below is now graded by it.
	local want = math.clamp(over, 0, 1)
	if want > st.over then
		st.over = math.min(want, st.over + dt / 1.1)
	else
		st.over = math.max(want, st.over - dt / 0.45)
	end

	-- HOW BADLY THE SUIT IS FAILING, NOT MERELY WHETHER IT IS. This was the real
	-- reason crossing a stage line went from nothing to everything, and no amount of
	-- grading the `over` layers could fix it: `failing` is a BOOLEAN the instant
	-- excess passes zero (Radiation.resolve: failing = excess > 0), and ramping to a
	-- flat 1 on it detonated four heavy layers at once — every crack, the 5-stud
	-- blur, the blood, and HudController's shake floor — for a player who had taken
	-- one step too far. The grade was arriving at full volume underneath the ladder.
	--
	-- The target now rides `over`, which is safe because they answer to the same
	-- condition: a toe past your rating cracks a corner of the visor, three times your
	-- rating still destroys the whole thing (over = 1 gives target = 1, exactly as
	-- before). FAIL_FLOOR keeps the state legible at the very bottom — the countdown
	-- says SUIT FAILING, so the glass has to say it too.
	--
	-- Ramps in over a couple of seconds and clears fast. Cracks that snap to full the
	-- instant a flag flips look like a texture swap; cracks that spread look like
	-- something breaking.
	local failTarget = if failing then FAIL_FLOOR + (1 - FAIL_FLOOR) * st.over else 0
	if failTarget > st.fail then
		st.fail = math.min(failTarget, st.fail + dt / 2.0)
	else
		st.fail = math.max(failTarget, st.fail - dt / 0.6)
	end

	-- Blood starts at a scratch and is total at a quarter health.
	local bleed = math.clamp((0.75 - healthFrac) / 0.5, 0, 1)
	-- A failing suit opens you up whatever the health bar still says — but by HOW far
	-- past your rating you are, not flat. A stride over the line is a nosebleed; three
	-- times your tolerance is every splat this file owns, at full health, immediately.
	bleed = math.max(bleed, st.fail * (0.3 + 0.65 * st.over))

	if intensity < 0.002 and st.fail < 0.002 and bleed < 0.002 and st.over < 0.002 then
		st.run = 0
		sleep()
		return
	end

	if not st.live then
		st.live = true
		ui.root.Visible = true
		ui.colour.Enabled = true
		ui.blur.Enabled = true
	end

	local fail = st.fail
	-- BLIND. Being somewhere your suit cannot hold is not a worse version of a high
	-- meter, it is a different sentence: the air itself is past what you are rated
	-- for, and the game says so by taking your sight rather than by adding another
	-- number. Every layer below reads this, which is why one stage too deep does not
	-- look like 99% rads — it looks like you cannot see.
	-- THE LIGHT GRADE IS A BROKEN PICTURE, NOT A DARK ONE. Splitting `over` here is
	-- what makes over-tier a ladder instead of a dimmer: `light` owns everything that
	-- degrades the SIGNAL (its own static, tearing, colour, throb) and peaks early, so
	-- a player one stage past their rating gets a noisy screen immediately; `blind`
	-- owns everything that takes SIGHT (the veil, the keyhole, the blur) and does not
	-- start until the light grade has already said its piece. Remapped so over = 1
	-- still lands on blind = 1.
	local blind = math.clamp((st.over - LIGHT_SPAN) / (1 - LIGHT_SPAN), 0, 1)
	-- LIGHT IS A BAND, NOT A FLOOR: it fades back out as `blind` takes over, so every
	-- expression below reduces to exactly its old form at over = 1. The intense grade
	-- is not "the old one plus a bit" — it is untouched, to the digit.
	local light = math.clamp(st.over / LIGHT_SPAN, 0, 1) * (1 - blind)
	local tint = GREEN:Lerp(WHITE, fail)
	-- THE BLIND TUNNEL IS DARK, NOT WHITE. Over-tier forces `failing`, which takes
	-- the iris white, and a white iris at blinding strength reads as fog on the lens
	-- — a milky screen you assume is a bug. Sight closing down is dark. It also keeps
	-- white doing its one job: the cracks are the only white thing left, and they now
	-- have something to be white against.
	local irisColour = tint:Lerp(VOID, blind * 0.88)
	local rot = ROT:Lerp(WHITE, fail * 0.45)
	-- One breath under everything, so the layers move together instead of each
	-- animating on its own private clock.
	local breath = 0.5 + 0.5 * math.sin(st.t * (1.1 + intensity * 1.6))

	-- Iris ------------------------------------------------------------
	-- Light tightens the frame a little (0.05) where blind slams it shut (0.46) — a
	-- hint that the edges are closing, not the keyhole.
	local close = 1 - intensity * 0.14 - fail * 0.05 - light * 0.05 - blind * 0.46 - breath * 0.012
	for _, ring in rings do
		local span = ring.span * close
		ring.frame.Size = UDim2.fromScale(span, span)
		ring.stroke.Color = irisColour
		-- Twelve discrete rings at blinding opacity show their own edges as concentric
		-- banding. Swelling each stroke makes neighbours overlap deeply enough that
		-- the seams close, which is cheaper than owning more rings.
		ring.stroke.Thickness = ring.thickness * (1 + blind * 1.4)
		-- `reach` gates the inner rings: at half dose only the outer ones are lit, so
		-- the clear middle of the screen shrinks as the meter fills.
		local depth = math.clamp((intensity - ring.reach * 0.85) / 0.3, 0, 1)
		local alpha = ring.weight * depth * (0.085 + 0.03 * breath) * (0.55 + 0.45 * intensity)
		alpha = math.max(alpha, ring.weight * fail * 0.07)
		-- Blindness lights the INNER rings too (the plain weight curve barely does),
		-- so what closes in is a tunnel with a hard rim rather than a soft edge.
		alpha = math.max(alpha, (0.35 + 0.65 * ring.weight) * blind * 0.3)
		-- The light grade lights the OUTER rings only (plain `weight`, no inner lift),
		-- so the edge of the picture roughens while the middle stays clean.
		alpha = math.max(alpha, ring.weight * light * 0.16)
		ring.stroke.Transparency = 1 - math.clamp(alpha, 0, 1)
	end

	-- Burns -----------------------------------------------------------
	for _, burn in burns do
		local appear = math.clamp((intensity - burn.at) / 0.2, 0, 1)
		appear = math.max(appear, fail * 0.7)
		if appear <= 0.001 then
			burn.halo.Visible = false
			continue
		end
		burn.halo.Visible = true

		local pulse = 0.5 + 0.5 * math.sin(st.t * burn.speed + burn.phase)
		local grow = (0.62 + 0.38 * appear + 0.06 * pulse) * px
		burn.halo.Size = UDim2.fromOffset(burn.w * grow, burn.h * grow)
		-- Creeps toward the middle as it establishes: damage closing in on what you
		-- can still see, rather than sitting politely at the border.
		local crawl = appear * 0.03
		burn.halo.Position = UDim2.fromScale(
			burn.u + (0.5 - burn.u) * crawl + math.sin(st.t * 0.3 + burn.phase) * 0.004,
			burn.v + (0.5 - burn.v) * crawl + math.cos(st.t * 0.27 + burn.phase) * 0.004
		)

		local alpha = appear * (0.45 + 0.25 * pulse) * (0.5 + 0.5 * intensity)
		burn.halo.BackgroundColor3 = rot
		burn.core.BackgroundColor3 = rot
		burn.halo.BackgroundTransparency = 1 - alpha * 0.3
		burn.core.BackgroundTransparency = 1 - alpha * 0.5
	end

	-- Grain -----------------------------------------------------------
	-- The meter's bank, untouched. It is worth knowing WHY the light grade could not
	-- simply be another term in here: over-tier always sets `failing`, `failing` alone
	-- already drives this near 1, and a probability that is already 1 cannot make more
	-- static out of thirty frames. See LIGHT_GRAIN_COUNT.
	local grainChance = math.clamp((intensity - 0.12) * 0.55 + fail * 0.4 + blind * 0.9, 0, 1)
	-- STATIC IS WHAT THE LIGHT GRADE IS MADE OF, and this is where it comes from: a
	-- bank that answers to `light` alone, so it is dark below over-tier and dark again
	-- once the veil is doing the talking. Lit ONLY in the band the grade owns.
	local lightChance = math.clamp(light * 0.85, 0, 1)
	for _, grain in grains do
		grain.life -= dt
		if grain.life <= 0 then
			if rng:NextNumber() < (if grain.lightOnly then lightChance else grainChance) then
				local heavy = rng:NextNumber() < 0.25
				grain.span = 0.05 + rng:NextNumber() * 0.12
				grain.life = grain.span
				grain.frame.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
				local dot = math.max(2, math.round((if heavy then 4 else 2) * px))
				grain.frame.Size = UDim2.fromOffset(dot, dot)
				grain.frame.BackgroundColor3 = if rng:NextNumber() < 0.3 then WHITE else tint
				grain.frame.Visible = true
			elseif grain.frame.Visible then
				grain.frame.Visible = false
			end
		else
			grain.frame.BackgroundTransparency = 1 - (grain.life / grain.span) * 0.85
		end
	end

	-- Tear ------------------------------------------------------------
	local tearing = intensity > 0.45 or fail > 0.2 or light > 0.04
	for _, tear in tears do
		tear.life -= dt
		if tear.life <= 0 then
			if tearing and rng:NextNumber() < 0.035 + intensity * 0.06 + light * 0.14 + blind * 0.2 then
				tear.span = 0.04 + rng:NextNumber() * 0.14
				tear.life = tear.span
				tear.frame.Position = UDim2.fromScale((rng:NextNumber() - 0.5) * 0.08, rng:NextNumber())
				tear.frame.Size = UDim2.new(1, 0, 0, (4 + rng:NextNumber() * 26) * px)
				tear.frame.BackgroundColor3 = tint
				tear.frame.Visible = true
			elseif tear.frame.Visible then
				tear.frame.Visible = false
			end
		else
			tear.frame.BackgroundTransparency = 1 - (tear.life / tear.span) * 0.5
		end
	end

	-- Cracks ----------------------------------------------------------
	for _, crack in cracks do
		local shown = math.clamp((fail - crack.at * 0.8) / 0.2, 0, 1)
		if shown <= 0.001 then
			if crack.frame.Visible then
				crack.frame.Visible = false
			end
			continue
		end
		crack.frame.Visible = true
		crack.frame.BackgroundTransparency = 1 - shown
		crack.outline.Transparency = 1 - shown * (0.7 + 0.2 * breath)
	end

	for _, impact in impacts do
		local shown = math.clamp((fail - impact.at) / 0.25, 0, 1)
		impact.frame.Visible = shown > 0.001
		impact.frame.BackgroundTransparency = 1 - shown * (0.3 + 0.12 * breath)
	end

	-- Blood -----------------------------------------------------------
	-- `run` is a bleeding clock: it advances only while blood is on the glass, so the
	-- drips grow while you are hurt and freeze the moment you stop losing health.
	st.run += dt * bleed
	for _, ring in bleedRings do
		ring.stroke.Transparency = 1 - math.clamp(ring.weight * bleed * 0.55, 0, 1)
	end

	for _, splat in splats do
		local landed = math.clamp((bleed - splat.at) / 0.18, 0, 1)
		if landed <= 0.001 then
			splat.smear.Visible = false
			splat.drip.Visible = false
			continue
		end
		splat.smear.Visible = true
		splat.drip.Visible = true

		local wet = 0.85 + 0.15 * math.sin(st.t * 0.8 + splat.phase)
		local grow = (0.7 + 0.3 * landed) * px
		splat.smear.Size = UDim2.fromOffset(splat.w * grow, splat.h * grow)
		splat.smear.BackgroundTransparency = 1 - landed * 0.5 * wet
		splat.clot.BackgroundTransparency = 1 - landed * 0.85
		for index, fleck in splat.flecks do
			-- Droplets land a beat after the splat they came off.
			fleck.BackgroundTransparency = 1 - math.clamp(landed * 1.4 - index * 0.25, 0, 1) * 0.8
		end

		-- Runs a third of the way down in ten seconds of solid bleeding, then keeps
		-- creeping. Capped so a long fight does not curtain the screen in red.
		local run = math.clamp(st.run * 0.09 - splat.at, 0, 1)
		splat.drip.Size = UDim2.fromOffset(splat.dripWidth * px, splat.dripMax * run * px)
		splat.drip.BackgroundTransparency = 1 - landed * 0.85
	end

	-- Throb -----------------------------------------------------------
	local rate = 1.0 + intensity * 1.9 + fail * 0.8 + light * 0.7 + blind * 1.6
	local beat = (0.5 + 0.5 * math.sin(st.t * rate * math.pi * 2)) ^ 6
	ui.throb.BackgroundColor3 = tint
	ui.throb.BackgroundTransparency = 1 - beat * (0.035 * intensity + 0.06 * fail + 0.03 * light + 0.07 * blind)

	-- Veil ------------------------------------------------------------
	-- `blind` ONLY, never `light`. This is the one layer allowed over the middle of
	-- the screen, and letting the light grade touch it would collapse the ladder back
	-- into a single dimmer — the whole point of the weakest grade is that it breaks
	-- the picture up without taking any of it away.
	ui.veil.BackgroundTransparency = 1 - blind * (0.66 + 0.06 * beat)

	-- Lighting --------------------------------------------------------
	-- Green sight failing, then bleaching WHITE as the suit goes — the same two-state
	-- colour story the meter and the blackout curtain tell, told on the world instead.
	local sick = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(150, 235, 120), 0.2 * intensity)
	ui.colour.TintColor = sick:Lerp(Color3.new(1, 1, 1), fail)
	-- The light grade DRAINS and HARDENS the picture (colour out, contrast up) where
	-- blind DARKENS it. Two different wrongnesses, so the grades are told apart at a
	-- glance rather than only by amount.
	ui.colour.Saturation = math.max(-1, -0.3 * intensity * (1 - fail) - 0.2 * light - 0.45 * fail - 0.5 * blind)
	ui.colour.Contrast = 0.12 * intensity + 0.2 * fail + 0.1 * light - 0.25 * blind
	ui.colour.Brightness = -0.02 * intensity + 0.05 * fail + beat * 0.03 * fail - 0.05 * bleed - 0.18 * blind
	-- 24 studs of blur is not "hazy", it is "you cannot read the ground you are
	-- standing on". That is the intended read: get out, by memory if you have to.
	ui.blur.Size = 1.5 * intensity * intensity + 5 * fail + beat * 1.5 * intensity + 2.5 * light + 24 * blind
end

return RadFx
