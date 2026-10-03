--[[
	RadFx.luau — what the dose looks like from inside the helmet.

	BAKED TEXTURES, NOT FRAME STACKS. The first version drew everything out of Frames,
	UICorner and UIGradient, and it hit the ceiling of those tools: twelve rounded
	rings made a pill-shaped vignette with visible bands, the burns were ovals, the
	static was round dots. Each layer below is now one or two images from RadFxArt
	(baked by tools/radfx-art/make_art.py) plus the Lighting effects. The one layer
	that is still built from Frames is the cracks, on purpose — the user kept them.

	PLAN §14's ONE COLOUR RULE still holds: exposure damage is GREEN, aura failure is
	WHITE, and the hurt shade is DARK and answers to HEALTH, never to rads. Green is the
	dose, white is the aura, dark is you. (No blood: the hurt layer is a plain dark
	edge so the game can answer "no" to blood on its maturity questionnaire.)

	THE LAYERS, back to front:

	  veil      blind only: the air goes dark green, even inside the keyhole.
	  rot       two noise-edged images scaled inward as the meter climbs. An uneven
	            necrotic edge with a pale burning rim eats toward the middle.
	  vignette  one radial-gradient image. It closes with the dose and tightens on
	            every heartbeat (the heartbeat used to be a full-screen green flash).
	            When blind, it shrinks to a keyhole and four bars fill in around it.
	  signal    thin scanline flickers. The light over-tier grade only.
	  hurt      a charcoal edge (the vignette texture again) that closes in as health
	            drops. Deliberately no red, no splats, no drips.
	  snow      what radiation looks like on a camera sensor: pixel hits and short
	            streaks. Three tiling images re-offset every frame so it never repeats.
	  cracks    white fractures raking in from the frame's edges, only while the aura
	            is failing.

	And in the world, created by the CLIENT so they are this player's sight and not
	the weather:

	  motes     a ParticleEmitter volume held in front of the camera. Glowing fallout
	            dust at real depths, so it parallaxes when you move.
	  focus     DepthOfFieldEffect: the ground near you stays sharp and the distance
	            goes soft. Blind softens everything, with a little BlurEffect on top.
	  colour    ColorCorrectionEffect: green and drained with the dose, bleached cold
	            when the aura fails, dark when blind.

	OVER-TIER COMES IN THREE GRADES, NOT ONE SLIDER. `over` is split at LIGHT_SPAN:
	  LIGHT     `light`, peaking at ~1.7x your rating and fading back out as blind
	            arrives. The picture BREAKS UP (static, scanlines, drained colour, a
	            faster heartbeat) but the middle of the screen is never taken.
	  REGULAR   the low half of `blind`. The keyhole starts closing and focus goes.
	  INTENSE   `blind` at full, ~3x your rating. The keyhole, the dark, the blur.

	THE FAILURE RAMP IS GRADED BY THE SAME NUMBER. `failing` is a boolean, so it only
	sets the floor (FAIL_FLOOR); `over` carries it to 1. A toe past your rating is a
	few cracks, not the whole visor.

	REDUCED (Settings' RADIATION EFFECTS, Config/Prefs radFx). Every layer runs at
	REDUCED strength and the busiest ones (snow, scanlines, motes, blur) stay off. The
	keyhole only eases to REDUCED_BLIND, never off: it is the soft gate that tells you
	this air is past your aura, so there is deliberately no "off" setting.

	COST: ~125 GUI objects, built once, and the container is Visible = false below
	EXPOSURE_WARN. The emitter is off while asleep. Nothing allocates per frame.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")

local RadFxArt = require(script.Parent.RadFxArt)
local UIKit = require(script.Parent.UIKit)

local RadFx = {}

local GREEN = UIKit.C.green
local WHITE = UIKit.C.burn
local BLACK = Color3.new(0, 0, 0)
-- What blindness is made of. Not pure black: it keeps a breath of the field's green,
-- so losing your sight still looks like the air did it to you.
local VOID = GREEN:Lerp(BLACK, 0.9)
-- The vignette's colour at a plain high meter: exposure's green, darkened.
local SHADE = GREEN:Lerp(BLACK, 0.55)
-- The rot textures are greyscale, so this is the colour of their pale burning rim;
-- the dark body comes out as necrotic green.
local ROT_TINT = Color3.fromRGB(120, 210, 110)
local SNOW_TINT = Color3.fromRGB(215, 255, 225)
local MOTE_TINT = Color3.fromRGB(120, 255, 140)
-- Aura failure bleaches the world COLD, not warm: white is the aura's colour.
local BLEACH = Color3.fromRGB(228, 240, 255)
local SICK = Color3.fromRGB(170, 240, 150)
-- Low health darkens the edge of your view. Neutral charcoal, never red.
local HURT = Color3.fromRGB(14, 14, 16)

-- WHERE THE LIGHT GRADE ENDS AND SIGHT STARTS GOING, on HudController's `over` ramp
-- (0 = rated for this air, 1 = three times your tolerance). ~1.7x your rating.
local LIGHT_SPAN = 0.22
-- How broken the aura reads the instant it starts failing; `over` carries the rest.
local FAIL_FLOOR = 0.25
-- Settings' "reduced" radiation effects: what is left of each layer, and of the
-- keyhole (kept higher so going too deep still visibly narrows your view).
local REDUCED = 0.5
local REDUCED_BLIND = 0.7

local SIGNAL_COUNT = 3

-- Seeded, so the damage layout is identical every session. A layout that reshuffles
-- on respawn reads as randomness; one that persists reads as YOUR helmet.
local rng = Random.new(0x2A0D)
-- Per-frame flicker only (snow offsets, scanlines). Unseeded on purpose.
local fx = Random.new()

local ui = {}
local rots, snows, signals, cracks, impacts = {}, {}, {}, {}, {}
local st = { t = 0, fail = 0, over = 0, live = false, built = false, reduced = false }

-- Every pixel measurement in this file is quoted against a 720-tall viewport and
-- scaled at layout time, so the damage does not depend on how big the window is.
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

local function image(name: string, art: string, z: number, parent: Instance): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.Image = art
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ImageTransparency = 1
	label.Visible = false
	label.ZIndex = z
	label.Parent = parent
	return label
end

local function frame(name: string, colour: Color3, z: number, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Visible = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- ── Build ───────────────────────────────────────────────────────────

--- The vignette and the four bars that fill in around it once it shrinks smaller
--- than the screen (the blind keyhole).
local function buildVignette(parent: Instance)
	ui.vignette = image("Vignette", RadFxArt.vignette, 2, parent)
	ui.bars = {}
	for _, side in { "Top", "Bottom", "Left", "Right" } do
		ui.bars[side] = frame("Keyhole" .. side, VOID, 2, parent)
	end
end

local function buildRot(parent: Instance)
	for i, art in RadFxArt.rot do
		rots[i] = image(string.format("Rot%d", i), art, 1, parent)
	end
end

--- Each snow layer is bigger than the screen by one tile, so shifting it by up to a
--- tile each frame never shows an edge.
local function buildSnow(parent: Instance)
	for i = 1, 3 do
		local label = image(string.format("Snow%d", i), RadFxArt.snow[i], 4, parent)
		label.AnchorPoint = Vector2.new(0, 0)
		label.ScaleType = Enum.ScaleType.Tile
		snows[i] = label
	end
end

local function buildSignal(parent: Instance)
	for i = 1, SIGNAL_COUNT do
		local line = frame(string.format("Signal%d", i), Color3.fromRGB(210, 255, 220), 3, parent)
		line.Size = UDim2.new(1, 0, 0, 1)
		local shadow = frame("Shadow", BLACK, 3, line)
		shadow.Size = UDim2.new(1, 0, 0, 1)
		shadow.Position = UDim2.fromScale(0, 1)
		shadow.Visible = true
		signals[i] = { line = line, shadow = shadow }
	end
end

--- Low health: the vignette texture again, tinted charcoal, closing in as you get hurt.
local function buildHurt(parent: Instance)
	ui.hurt = image("Hurt", RadFxArt.vignette, 3, parent)
	ui.hurt.ImageColor3 = HURT
end

--- Cracks are walked in NORMALISED space (0..1 on both axes) and converted to pixels
--- at layout time, so a window resize only stretches the pattern. Generated once — a
--- crack that redraws itself is a scratch on your visor that heals.
---
--- THEY RUN ALONG THE EDGE, NOT AT THE MIDDLE: aimed inward at a shallow angle and
--- kept short, they stay in the outer third with the rest of the damage.
local function buildCracks(parent: Instance)
	local starts = {
		Vector2.new(0.01, 0.16), Vector2.new(0.99, 0.22), Vector2.new(0.08, 0.97),
		Vector2.new(0.92, 0.94), Vector2.new(0.38, 0.01), Vector2.new(0.99, 0.68),
		Vector2.new(0.01, 0.74), Vector2.new(0.62, 0.99),
	}

	for index, start in starts do
		local aim = math.atan2(0.5 - start.Y, 0.5 - start.X)
			+ (if index % 2 == 0 then 0.95 else -0.95)
		local order = (index - 1) / #starts

		local impact = frame(string.format("Impact%d", index), WHITE, 5, parent)
		impact.AnchorPoint = Vector2.new(0.5, 0.5)
		impact.Position = UDim2.fromScale(start.X, start.Y)

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
				-- A crack wanders; it does not zigzag. Zigzag reads as rain.
				angle += (rng:NextNumber() - 0.5) * 0.45
				local len = (0.025 + rng:NextNumber() * 0.05) * scale
				local to = at + Vector2.new(math.cos(angle), math.sin(angle)) * len

				local seg = frame(string.format("Crack%d_%d", index, step), WHITE, 5, parent)
				seg.AnchorPoint = Vector2.new(0, 0.5)

				-- A white hairline over a bright sky is nearly nothing; the same line
				-- with a dark edge on it reads at any brightness.
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

--- The fallout. A transparent volume held in front of the camera every frame; the
--- particles are emitted into the WORLD (not locked to the part), which is what gives
--- them depth and parallax instead of sitting on the glass like the snow does.
local function buildMotes()
	local part = Instance.new("Part")
	part.Name = "RadFxMotes"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(36, 18, 28)
	ui.motePart = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fallout"
	emitter.Texture = RadFxArt.mote
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(2.5, 4.5)
	emitter.Speed = NumberRange.new(0.2, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.4, 0)
	emitter.Drag = 0.5
	emitter.RotSpeed = NumberRange.new(0, 0)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Brightness = 1.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0, 0),
		NumberSequenceKeypoint.new(0.15, 0.12, 0.06),
		NumberSequenceKeypoint.new(0.85, 0.12, 0.06),
		NumberSequenceKeypoint.new(1, 0, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(MOTE_TINT)
	emitter.Parent = part
	ui.motes = emitter
end

--- Pixel layout: the scale factor, snow tile size and the crack segments. Re-run
--- whenever the viewport changes.
local function layout()
	local size = viewport()
	px = size.Y / 720

	-- 1.4x native at 720 tall (about 540 px at 1080p): every hit is a crisp 2-3 px,
	-- whatever the resolution. Floored because Studio can report a 1x1 viewport on
	-- load, which rounds the tile to 0 and Roblox refuses a zero TileSize.
	local tile = math.max(16, math.round(RadFxArt.SNOW_TILE * px * 1.4))
	for _, label in snows do
		label.TileSize = UDim2.fromOffset(tile, tile)
		label.Size = UDim2.new(1, tile, 1, tile)
	end
	ui.snowTile = tile

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

	-- The veil, built first so the rot and the vignette sit over it.
	local veil = frame("Veil", VOID, 1, root)
	veil.Size = UDim2.fromScale(1, 1)
	veil.Visible = true
	ui.veil = veil

	buildRot(root)
	buildVignette(root)
	buildSignal(root)
	buildHurt(root)
	buildSnow(root)
	buildCracks(root)
	buildMotes()
	layout()

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	ui.colour = Instance.new("ColorCorrectionEffect")
	ui.colour.Name = "RadFxColour"
	ui.colour.Enabled = false
	ui.colour.Parent = Lighting

	ui.focus = Instance.new("DepthOfFieldEffect")
	ui.focus.Name = "RadFxFocus"
	ui.focus.FarIntensity = 0
	ui.focus.NearIntensity = 0
	ui.focus.Enabled = false
	ui.focus.Parent = Lighting

	ui.blur = Instance.new("BlurEffect")
	ui.blur.Name = "RadFxBlur"
	ui.blur.Size = 0
	ui.blur.Enabled = false
	ui.blur.Parent = Lighting

	-- Snow swaps between its three tiles every frame; one that has not loaded yet
	-- would blink blank, so fetch them all up front.
	task.spawn(function()
		local art = { RadFxArt.vignette, RadFxArt.mote }
		for _, list in { RadFxArt.rot, RadFxArt.snow } do
			for _, id in list do
				table.insert(art, id)
			end
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, art)
	end)

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
	ui.focus.Enabled = false
	ui.blur.Enabled = false
	ui.motes.Enabled = false
	ui.motePart.Parent = nil
end

--- Settings' RADIATION EFFECTS: true = "reduced" (see the header). Read every frame.
function RadFx.setReduced(on: boolean)
	st.reduced = on
end

--- `intensity` is HudController's own 0..1 escalation ramp (0 below EXPOSURE_WARN),
--- `failing` is the aura-failure flag, `healthFrac` is 0..1 of max HP, and `over` is
--- 0..1 of "how far past your aura's rating this air is" — 0 anywhere you are rated
--- for, 1 in a stage that should never have let you in. Nothing else belongs here.
function RadFx.update(dt: number, intensity: number, failing: boolean, healthFrac: number, over: number)
	if not st.built then
		return
	end

	st.t += dt

	-- Eased, not snapped, and it lifts faster than it lands: a player who turns and
	-- runs has to SEE that retreating is working, immediately.
	local want = math.clamp(over, 0, 1)
	if want > st.over then
		st.over = math.min(want, st.over + dt / 1.1)
	else
		st.over = math.max(want, st.over - dt / 0.45)
	end

	-- How badly the aura is failing, not merely whether it is — see FAIL_FLOOR.
	-- Ramps in over a couple of seconds and clears fast, so cracks spread.
	local failTarget = if failing then FAIL_FLOOR + (1 - FAIL_FLOOR) * st.over else 0
	if failTarget > st.fail then
		st.fail = math.min(failTarget, st.fail + dt / 2.0)
	else
		st.fail = math.max(failTarget, st.fail - dt / 0.6)
	end

	-- The hurt shade starts at a scratch and is total at a quarter health. A failing aura
	-- hurts whatever the health bar says, graded by how far past your rating you are.
	local hurt = math.clamp((0.75 - healthFrac) / 0.5, 0, 1)
	hurt = math.max(hurt, st.fail * (0.3 + 0.65 * st.over))

	if intensity < 0.002 and st.fail < 0.002 and hurt < 0.002 and st.over < 0.002 then
		sleep()
		return
	end

	local camera = workspace.CurrentCamera
	if not st.live then
		st.live = true
		ui.root.Visible = true
		ui.colour.Enabled = true
		ui.focus.Enabled = true
		ui.blur.Enabled = true
		ui.motes.Enabled = true
		ui.motePart.Parent = camera
	end

	local dose = intensity
	local fail = st.fail
	-- THE LIGHT GRADE IS A BROKEN PICTURE, THE BLIND GRADE IS A DARK ONE. `light` owns
	-- what degrades the signal and peaks early; `blind` owns what takes sight and only
	-- starts once `light` has said its piece. Remapped so over = 1 lands on blind = 1.
	local blind = math.clamp((st.over - LIGHT_SPAN) / (1 - LIGHT_SPAN), 0, 1)
	local light = math.clamp(st.over / LIGHT_SPAN, 0, 1) * (1 - blind)
	local reduced = st.reduced
	if reduced then
		dose *= REDUCED
		fail *= REDUCED
		light *= REDUCED
		hurt *= REDUCED
		blind *= REDUCED_BLIND
	end
	local breath = 0.5 + 0.5 * math.sin(st.t * (1.1 + dose * 1.6))
	local rate = 1.0 + dose * 1.9 + fail * 0.8 + light * 0.7 + blind * 1.6
	local beat = (0.5 + 0.5 * math.sin(st.t * rate * math.pi * 2)) ^ 6

	-- Veil ------------------------------------------------------------
	ui.veil.BackgroundTransparency = 1 - blind * 0.38

	-- Rot -------------------------------------------------------------
	-- Scaled from well past the frame inward, so the uneven edge CREEPS in rather than
	-- fading up in place.
	local rotAppear = math.max(math.clamp((dose - 0.12) / 0.88, 0, 1), fail * 0.55, light * 0.35)
	for i, label in rots do
		if rotAppear <= 0.001 then
			label.Visible = false
			continue
		end
		local s = 1.55 - 0.34 * rotAppear - 0.12 * blind + math.sin(st.t * 0.35 + i * 2) * 0.012 + (i - 1) * 0.04
		label.Visible = true
		label.Size = UDim2.fromScale(s, s * 1.35)
		label.Position = UDim2.fromScale(0.5 + math.sin(st.t * 0.2 + i) * 0.0055, 0.5)
		label.ImageColor3 = ROT_TINT:Lerp(WHITE, fail * 0.2)
		label.ImageTransparency = 1 - rotAppear * (if i == 1 then 0.62 else 0.4)
	end

	-- Vignette --------------------------------------------------------
	-- The heartbeat lives HERE now: vision pulling in on each beat, not a flash.
	local vigAlpha = math.clamp(0.35 * dose + 0.2 * fail + 0.18 * light + 0.8 * blind + beat * (0.1 * dose + 0.12 * blind), 0, 0.97)
	local vigColour = SHADE:Lerp(VOID, math.clamp(blind * 1.1, 0, 1))
	local s = 1.28 - 0.2 * dose - 0.05 * light - 0.62 * blind - beat * 0.035 * (dose + blind)
	local vw, vh = s * 1.12, s * 1.45
	local vignette = ui.vignette
	vignette.Visible = vigAlpha > 0.002
	vignette.Size = UDim2.fromScale(vw, vh)
	vignette.ImageColor3 = vigColour
	vignette.ImageTransparency = 1 - vigAlpha

	-- Once the vignette is smaller than the screen, everything outside it is solid.
	-- The bars overlap the image by a hair so no seam shows at the join.
	local x0, y0 = 0.5 - vw / 2 + 0.002, 0.5 - vh / 2 + 0.002
	local x1, y1 = 0.5 + vw / 2 - 0.002, 0.5 + vh / 2 - 0.002
	local bars = ui.bars
	local keyhole = blind > 0.02 and vigAlpha > 0.002
	bars.Top.Visible = keyhole and y0 > 0
	bars.Top.Size = UDim2.fromScale(1, math.max(0, y0))
	bars.Bottom.Visible = keyhole and y1 < 1
	bars.Bottom.Position = UDim2.fromScale(0, y1)
	bars.Bottom.Size = UDim2.fromScale(1, math.max(0, 1 - y1))
	bars.Left.Visible = keyhole and x0 > 0
	bars.Left.Size = UDim2.fromScale(math.max(0, x0), 1)
	bars.Right.Visible = keyhole and x1 < 1
	bars.Right.Position = UDim2.fromScale(x1, 0)
	bars.Right.Size = UDim2.fromScale(math.max(0, 1 - x1), 1)
	for _, bar in bars do
		bar.BackgroundColor3 = vigColour
		bar.BackgroundTransparency = 1 - vigAlpha
	end

	-- Signal ----------------------------------------------------------
	-- Light grade only. Hairlines that last one frame, not bars that fade.
	for _, signal in signals do
		if not reduced and light > 0.04 and fx:NextNumber() < light * 0.35 then
			local thick = math.max(1, math.round(px)) * fx:NextInteger(1, 2)
			signal.line.Visible = true
			signal.line.Position = UDim2.fromScale(0, fx:NextNumber())
			signal.line.Size = UDim2.new(1, 0, 0, thick)
			signal.line.BackgroundTransparency = 1 - (0.25 + fx:NextNumber() * 0.3)
			signal.shadow.Size = UDim2.new(1, 0, 0, math.max(1, math.round(px)))
			signal.shadow.BackgroundTransparency = 0.75
		else
			signal.line.Visible = false
		end
	end

	-- Hurt ------------------------------------------------------------
	-- Pulls in from past the frame as health drops, and tightens a touch on the beat.
	local hs = 1.5 - 0.3 * hurt - beat * 0.02 * hurt
	ui.hurt.Visible = hurt > 0.002
	ui.hurt.Size = UDim2.fromScale(hs * 1.12, hs * 1.45)
	ui.hurt.ImageTransparency = 1 - math.clamp(hurt * 0.8 * (0.9 + 0.1 * beat), 0, 1)

	-- Snow ------------------------------------------------------------
	-- Up to three tile layers a frame, each at a fresh offset: density comes from how
	-- many layers land, so a low dose is a few hits and the blind grade is a storm.
	local snowRate = if reduced then 0 else math.clamp((dose - 0.05) * 0.8 + light * 1.1 + fail * 0.45 + blind, 0, 1)
	local tile = ui.snowTile
	for k, label in snows do
		if fx:NextNumber() > snowRate * 1.2 - (k - 1) * 0.33 then
			label.Visible = false
			continue
		end
		label.Visible = true
		label.Image = RadFxArt.snow[fx:NextInteger(1, #RadFxArt.snow)]
		label.Position = UDim2.fromOffset(-fx:NextInteger(0, tile), -fx:NextInteger(0, tile))
		label.ImageColor3 = SNOW_TINT:Lerp(WHITE, fail)
		label.ImageTransparency = 1 - math.clamp(0.35 + snowRate * 0.65, 0, 1)
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

	-- Motes -----------------------------------------------------------
	local moteAmount = math.clamp(dose * 0.8 + light * 0.6 + fail * 0.3 + blind * 0.4, 0, 1)
	ui.motes.Rate = if reduced then 0 else 60 * moteAmount
	ui.motes.Color = ColorSequence.new(MOTE_TINT:Lerp(BLEACH, fail * 0.6))
	if camera then
		ui.motePart.CFrame = camera.CFrame * CFrame.new(0, 0, -16)
	end

	-- Lighting --------------------------------------------------------
	-- Green and drained with the dose, bleached cold as the aura goes, dark when blind.
	local tint = Color3.new(1, 1, 1):Lerp(SICK, 0.28 * dose)
	ui.colour.TintColor = tint:Lerp(BLEACH, fail * 0.6)
	ui.colour.Saturation = math.max(-1, -0.35 * dose - 0.3 * light - 0.35 * fail - 0.3 * blind)
	ui.colour.Contrast = 0.08 * dose + 0.15 * light + 0.1 * fail - 0.2 * blind
	ui.colour.Brightness = -0.03 * dose - 0.07 * beat * (dose + blind) - 0.05 * hurt - 0.3 * blind + 0.05 * fail

	-- Focus: the ground at your feet stays readable, the distance goes. Focused on the
	-- camera's own subject, so it follows zoom. Blind takes the near field too, and a
	-- little real blur on top, because DoF alone never gets fully soft.
	local focus = ui.focus
	focus.FocusDistance = if camera then (camera.CFrame.Position - camera.Focus.Position).Magnitude else 12
	focus.InFocusRadius = 30 - 22 * blind
	focus.FarIntensity = math.clamp((1.2 * dose + 2.5 * fail + 1.8 * light + 7 * blind) / 8, 0, 1)
	focus.NearIntensity = math.clamp((0.25 * fail + 3.5 * blind) / 4, 0, 1)
	ui.blur.Size = if reduced then 0 else 10 * blind
end

return RadFx
