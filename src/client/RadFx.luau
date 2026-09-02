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
	white BECAUSE it only ever appears while the suit is failing.

	SIX LAYERS, EACH ARRIVING AT ITS OWN THRESHOLD, so escalation is a sequence rather
	than one slider being dragged:

	  iris    elliptical rings closing in from beyond the frame. This is the vignette's
	          replacement — round, and moving. Vision tunnelling, not a border.
	  burns   soft blotches that bloom at the edge of sight and creep inward, one at a
	          time as the meter climbs. Tissue going, not a gradient ramping.
	  grain   single sparks. Particles landing on the back of your eye — the picture
	          half of the click bed GeigerController is already playing.
	  tear    horizontal signal breakup past DANGER. The feed failing, not the eye.
	  cracks  hairline fractures spidering in from the frame's edges, WHITE, and only
	          while the suit is failing. This is the layer that means destroyed.
	  throb   a heartbeat over the whole picture, faster as the meter fills.

	Plus a colour-correction and blur pass on Lighting. Those instances are created by
	the CLIENT, so they are this player's sight going — not the world's weather. That
	is the whole reason exposure can be a personal, per-player state and still be felt
	across the entire screen.

	COST: ~120 frames, built once, and the container is Visible = false below
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

-- Seeded, so the damage pattern is identical every session. A blotch layout that
-- reshuffles on respawn reads as randomness; one that persists reads as YOUR helmet.
local rng = Random.new(0x2A0D)

local RING_COUNT = 12
local BURN_COUNT = 14
local GRAIN_COUNT = 30
local TEAR_COUNT = 3

local ui = {}
local rings, burns, grains, tears, cracks, impacts = {}, {}, {}, {}, {}, {}
local st = { t = 0, fail = 0, live = false, built = false }

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
	for i = 1, GRAIN_COUNT do
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

		grains[i] = { frame = dot, life = 0, span = 0.1 }
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

				table.insert(cracks, {
					frame = seg,
					from = at,
					to = to,
					thickness = if thin then 1 else 2,
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
		-- the innermost one still stops well short of the middle.
		ring.stroke.Thickness = 90 * px
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
	buildGrain(root)
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

--- `intensity` is HudController's own 0..1 escalation ramp (0 below EXPOSURE_WARN)
--- and `failing` is the suit-failure flag. Nothing else about exposure belongs here.
function RadFx.update(dt: number, intensity: number, failing: boolean)
	if not st.built then
		return
	end

	st.t += dt
	-- Failure ramps in over a couple of seconds and clears fast. Cracks that snap to
	-- full the instant a flag flips look like a texture swap; cracks that spread look
	-- like something breaking.
	local step = if failing then dt / 2.0 else -dt / 0.6
	st.fail = math.clamp(st.fail + step, 0, 1)

	if intensity < 0.002 and st.fail < 0.002 then
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
	local tint = GREEN:Lerp(WHITE, fail)
	local rot = ROT:Lerp(WHITE, fail * 0.45)
	-- One breath under everything, so the layers move together instead of each
	-- animating on its own private clock.
	local breath = 0.5 + 0.5 * math.sin(st.t * (1.1 + intensity * 1.6))

	-- Iris ------------------------------------------------------------
	local close = 1 - intensity * 0.14 - fail * 0.05 - breath * 0.012
	for _, ring in rings do
		local span = ring.span * close
		ring.frame.Size = UDim2.fromScale(span, span)
		ring.stroke.Color = tint
		-- `reach` gates the inner rings: at half dose only the outer ones are lit, so
		-- the clear middle of the screen shrinks as the meter fills.
		local depth = math.clamp((intensity - ring.reach * 0.85) / 0.3, 0, 1)
		local alpha = ring.weight * depth * (0.085 + 0.03 * breath) * (0.55 + 0.45 * intensity)
		alpha = math.max(alpha, ring.weight * fail * 0.07)
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
	local grainChance = math.clamp((intensity - 0.12) * 0.55 + fail * 0.4, 0, 1)
	for _, grain in grains do
		grain.life -= dt
		if grain.life <= 0 then
			if rng:NextNumber() < grainChance then
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
	local tearing = intensity > 0.45 or fail > 0.2
	for _, tear in tears do
		tear.life -= dt
		if tear.life <= 0 then
			if tearing and rng:NextNumber() < 0.035 + intensity * 0.06 then
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
		crack.frame.BackgroundTransparency = 1 - shown * (0.75 + 0.25 * breath)
	end

	for _, impact in impacts do
		local shown = math.clamp((fail - impact.at) / 0.25, 0, 1)
		impact.frame.Visible = shown > 0.001
		impact.frame.BackgroundTransparency = 1 - shown * (0.2 + 0.1 * breath)
	end

	-- Throb -----------------------------------------------------------
	local rate = 1.0 + intensity * 1.9 + fail * 0.8
	local beat = (0.5 + 0.5 * math.sin(st.t * rate * math.pi * 2)) ^ 6
	ui.throb.BackgroundColor3 = tint
	ui.throb.BackgroundTransparency = 1 - beat * (0.035 * intensity + 0.06 * fail)

	-- Lighting --------------------------------------------------------
	-- Green sight failing, then bleaching WHITE as the suit goes — the same two-state
	-- colour story the meter and the blackout curtain tell, told on the world instead.
	local sick = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(150, 235, 120), 0.2 * intensity)
	ui.colour.TintColor = sick:Lerp(Color3.new(1, 1, 1), fail)
	ui.colour.Saturation = -0.3 * intensity * (1 - fail) - 0.45 * fail
	ui.colour.Contrast = 0.12 * intensity + 0.2 * fail
	ui.colour.Brightness = -0.02 * intensity + 0.05 * fail + beat * 0.03 * fail
	ui.blur.Size = 1.5 * intensity * intensity + 5 * fail + beat * 1.5 * intensity
end

return RadFx
