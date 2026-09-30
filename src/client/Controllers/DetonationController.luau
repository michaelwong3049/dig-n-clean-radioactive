--!strict
--[[
	DetonationController.luau — what a nuke going off looks like, and what it leaves.

	THREE JOBS, all driven by the server and all purely visual except one:

	  1. THE BLAST (the Detonation remote, fired to every client). A soft flash that
	     blows the whole scene out white for a moment; a fireball with a green-white
	     heart that swells, lifts and rolls over into smoke; a shock dome of rippling
	     air racing out with dust riding its foot; the ground thrown outward. Rare and
	     up climb on a narrow stem into a cap whose edge rolls down and back in on
	     itself -- Epic and up in full, with a pale skirt round the stem -- and the top
	     rarities are drawn bigger than their blast radius (GRAND_*). The shock front
	     reaches YOU a beat after the flash, the farther the later: a jolt, the view
	     punched wide, a smear of blur. THE ONE NON-VISUAL THING: if YOUR character was inside the blast, this
	     knocks it flat and throws it clear. The server cannot do that reliably -- the
	     character's physics belongs to its own client -- so every client flings its own.
	     The health it cost is the server's (HazardService, ExposureService), not ours.

	  2. THE CRATER (a marker part per crater in Workspace[Config/Detonation.FOLDER]).
	     Scorched ground, a broken lip, glowing fissures, and over it the orb: a
	     shimmering shell of hot air full of drifting motes, lit from inside. It shrinks
	     and dims on Shared/Detonation.orbStrength -- the SAME curve the server burns on
	     -- so the edge you can see is the edge that hurts. Standing inside tints the
	     world green. Built off the marker's attributes, so a player who joins while a
	     crater is still hot sees exactly what everyone else does.

	  3. THE FUSE (anything tagged Config/Detonation.HOT_TAG). A nuke with a lit fuse
	     warms its spot in the ground; past WARN_AT the spot starts ticking; armed, it
	     flashes red, ticks faster and faster, and hangs a countdown over itself where
	     everyone can read it -- a spectator knows to back off before it goes. The lump
	     climbing out of the ground glows with it.

	REALISTIC OVER STYLISED. The blast is built as the phenomenon, in the order it
	happens -- flash, fireball, smoke, the ground reacting -- out of particles, rather
	than as a bright cartoon ball. Neon only where something is genuinely emitting
	light (the flash, the fissures, the orb's core).

	Everything built here is client-only and lives in one local folder; nothing here
	ever writes to a replicated instance except the local character.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local DetonationConfig = require(Shared.Config.Detonation)
local Detonation = require(Shared.Detonation)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)

local DetonationController = {}

-- ── Assets ─────────────────────────────────────────────────────────────
-- NOT the engine's explosion01_* / fire_main textures, tempting as the names are: each
-- is only half of the legacy effect's art (the alpha lives in a sibling file), and as
-- a particle texture they draw as dark opaque blobs -- the first cut of this made a
-- mushroom cap that was a black disc. The smoke is the one the wash bay already uses,
-- the flame is ItemFxController's uploaded tongue (white, shape in alpha, tinted by
-- the emitter), and sparkles is the emitter default.
local TEX_FIRE = "rbxassetid://80667240595677"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local BOOM_SOUND = "rbxasset://sounds/impact_explosion_03.mp3"
local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"

-- ── Colours ────────────────────────────────────────────────────────────
local FLASH = Color3.fromHex("FFF4D6")
local FIRE_HOT = Color3.fromHex("FFE7A3")
local FIRE_MID = Color3.fromHex("FF8A2A")
local FIRE_DEEP = Color3.fromHex("8A2A12")
local SMOKE_LIT = Color3.fromHex("6B4A33") -- the underside of smoke with fire under it
local SMOKE = Color3.fromHex("4A4540")
local SMOKE_CAP = Color3.fromHex("6E675F") -- the cap is thinner and sunlit; pure SMOKE there read as a black blot
local SMOKE_PALE = Color3.fromHex("8A847C")
local EMBER = Color3.fromHex("8E4424") -- smoke still glowing with the fire inside it
local SKIRT = Color3.fromHex("E3E1DA") -- condensation, not smoke: pale and thin
local FLASH_RAD = Color3.fromHex("E4FFC4") -- the flash's white, with the rad showing
local FLASH_TINT = Color3.fromHex("F2FFE4") -- what the scene is tinted as it blows out
local RAD_WHITE = Color3.fromHex("D8FF8A") -- the hottest point of the fireball's green heart
local SHOCK_AIR = Color3.fromHex("E9F5DC") -- the shock dome's shimmer
local DUST = Color3.fromHex("6E6456")
local CHUNK = Color3.fromHex("2B2621")
local SCORCH = Color3.fromHex("1C1814")
local ASH = Color3.fromHex("3A332B")
local RAD_GLOW = Color3.fromHex("A6FF3E") -- the light pooled in a crater, the fireball's core
local RAD_AIR = Color3.fromHex("8CFF4A") -- the orb's shell
local RAD_HAZE = Color3.fromHex("5ED62A")
local CRACK_GLOW = Color3.fromHex("4FB81F") -- the fissures: dim enough that Neon stays green
local SCREEN_FLASH = Color3.fromHex("FFE6B8") -- warm; the white screen means aura failure
local TINT_INSIDE = Color3.fromHex("C9FFB0")
local FUSE_WARM = Color3.fromHex("F59E0B")
local FUSE_ARMED = Color3.fromHex("FF2A1A")

-- ── Tuning (visual only) ────────────────────────────────────────────────
local COLUMN_FROM = 4 -- Rarity order: Rare and up climb on a stem into a small cap
local CAP_FROM = 5 -- Epic and up get the full rolling cap and the skirt
local GRAND_FROM = 4 -- past this Rarity order the spectacle outgrows the blast radius...
local GRAND_STEP = 0.18 -- ...by this much per order (Anomaly draws ~1.7x its radius)
local SHAKE_REACH = 8 -- the shock front is felt out to this many blast radii
local FLASH_REACH = 2.5 -- the warm screen wash of heat, only this close
local SCENE_FLASH_REACH = 9 -- the scene-wide flash of light, seen out to this many radii
local SHOCK_SPEED = 200 -- studs/s: the visible front, and when you feel it arrive
local SHOCK_REACH = 3.5 -- the visible dome's final radius, in blast radii (grows at the top)
local FOV_KICK = 9 -- degrees the view is punched wide by a point-blank shock
local BLUR_KICK = 14 -- BlurEffect size of the same
local GRAVITY = 70 -- studs/s^2 for thrown chunks; a touch floatier than Workspace's
local BEEP_WARN_INTERVAL = 0.9
local BEEP_ARMED_SLOW = 0.45
local BEEP_ARMED_FAST = 0.08
local TINT_MAX = 0.55

local player = Players.LocalPlayer

local fxFolder: Folder = nil :: any
local shakes: { { amp: number, t0: number, duration: number } } = {}
local fovKicks: { { amp: number, t0: number, duration: number } } = {}
local fovBase: number? = nil -- the FOV before our kick, while one is running
local fovApplied: number? = nil -- what we last set, to notice anyone else changing it

local sceneFlash: ColorCorrectionEffect = nil :: any
local shockBlur: BlurEffect = nil :: any
local sceneTween: Tween? = nil
local blurTween: Tween? = nil

type Chunk = { part: BasePart, from: Vector3, velocity: Vector3, spin: Vector3, t0: number, floor: number, landed: number? }
local chunks: { Chunk } = {}

-- ── Helpers ────────────────────────────────────────────────────────────

local function fxPart(className: string?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if className == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif className == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	return p
end

local function seq(...: number): NumberSequence
	local values = { ... }
	local keys = {}
	for i = 1, #values, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function colours(...: any): ColorSequence
	local values = { ... }
	local keys = {}
	for i = 1, #values, 2 do
		table.insert(keys, ColorSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return ColorSequence.new(keys)
end

-- Particle sizes are capped at 100 by the engine; clamp rather than let a huge blast
-- silently render at 100 on one keypoint and full size on the next.
local function cap(size: number): number
	return math.min(size, 100)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Top
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function characterRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function rarityOrder(rarity: string): number
	local def = Rarity.DEFS[rarity]
	return if def then def.order else 2
end

-- ── 1. The blast ─────────────────────────────────────────────────────────

local function shake(amplitude: number, duration: number)
	if amplitude <= 0 then
		return
	end
	table.insert(shakes, { amp = amplitude, t0 = os.clock(), duration = duration })
end

local screenFlash: Frame = nil :: any

local function flashScreen(strength: number)
	if strength <= 0 then
		return
	end
	screenFlash.BackgroundTransparency = 1 - 0.6 * strength
	screenFlash.Visible = true
	local tween = TweenService:Create(screenFlash, TweenInfo.new(0.35 + 0.4 * strength, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tween.Completed:Connect(function()
		if screenFlash.BackgroundTransparency >= 0.999 then
			screenFlash.Visible = false
		end
	end)
	tween:Play()
end

--- Blown off your feet. The character's physics is ours, so this is the only place the
--- knockback CAN happen. PlatformStand drops the Humanoid's own footing -- without it a
--- grounded Humanoid brakes a sideways shove to nothing inside a frame -- and hands the
--- body to the impulse; lifting it clears it off the ground so it actually travels.
local function knockback(position: Vector3, blastRadius: number)
	local root = characterRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end

	local offset = root.Position - position
	local speed, lift = Detonation.knockbackAt(offset.Magnitude, blastRadius)
	if speed <= 0 and lift <= 0 then
		return
	end

	local flat = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flat.Magnitude > 0.2 then flat.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit

	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, lift, 0)
	-- Tumble away from the blast, head over heels.
	root.AssemblyAngularVelocity = direction:Cross(Vector3.yAxis) * -(3 + speed / 20)

	task.delay(DetonationConfig.KNOCKBACK_SECONDS, function()
		if humanoid.Parent ~= nil then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

--- Chunks of ground thrown out of the hole, flown by hand (see the Heartbeat) rather
--- than handed to the physics engine: they cannot hit anyone, cannot pile up, and land
--- where they were always going to.
local function throwChunks(position: Vector3, blastRadius: number, count: number)
	local now = os.clock()
	for _ = 1, count do
		local chunk = fxPart()
		chunk.Material = Enum.Material.Slate
		chunk.Color = CHUNK:Lerp(DUST, math.random() * 0.4)
		local s = (0.35 + math.random() * 0.7) * math.sqrt(blastRadius / 10)
		chunk.Size = Vector3.new(s, s * (0.6 + math.random() * 0.6), s * (0.7 + math.random() * 0.5))
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = fxFolder

		local angle = math.random() * math.pi * 2
		local out = (0.5 + math.random()) * blastRadius * 1.2
		local up = 20 + math.random() * 25 + blastRadius * 0.8
		table.insert(chunks, {
			part = chunk,
			from = chunk.Position,
			velocity = Vector3.new(math.cos(angle) * out, up, math.sin(angle) * out),
			spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
			t0 = now,
			floor = position.Y + s * 0.3,
		})
	end
end

--- How much larger than its blast radius a nuke's spectacle is drawn. The radius that
--- hurts is the server's and stays put; this only stretches the show, so an Epic's
--- cloud towers over a Rare's by more than their radii alone would say.
local function grandeur(order: number): number
	return 1 + math.max(0, order - GRAND_FROM) * GRAND_STEP
end

--- The instant of the flash, seen by the whole scene: everything blown out bright and
--- bleached, then the colour seeping back. Measured from the CAMERA -- it is light,
--- and you see it whether or not it can reach you.
local function flashScene(strength: number)
	if strength <= 0.01 then
		return
	end
	if sceneTween then
		sceneTween:Cancel()
	end
	sceneFlash.Brightness = math.max(sceneFlash.Brightness, 0.45 * strength)
	sceneFlash.Contrast = math.max(sceneFlash.Contrast, 0.3 * strength)
	sceneFlash.Saturation = math.min(sceneFlash.Saturation, -0.6 * strength)
	sceneFlash.TintColor = Color3.new(1, 1, 1):Lerp(FLASH_TINT, strength)
	sceneFlash.Enabled = true
	local tween = TweenService:Create(sceneFlash, TweenInfo.new(0.3 + 1.1 * strength, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	})
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			sceneFlash.Enabled = false
		end
	end)
	sceneTween = tween
	tween:Play()
end

--- The shock front reaching YOU: a hard jolt, the view kicked wide, a smear of blur.
--- Arrives after the flash by however long the front took to cross the distance.
local function shockHits(strength: number, order: number)
	if strength <= 0.01 then
		return
	end
	shake((0.9 + order * 0.3) * strength, 0.45 + order * 0.08)
	table.insert(fovKicks, { amp = FOV_KICK * strength, t0 = os.clock(), duration = 0.6 })
	if blurTween then
		blurTween:Cancel()
	end
	shockBlur.Size = math.max(shockBlur.Size, BLUR_KICK * strength)
	shockBlur.Enabled = true
	local tween = TweenService:Create(shockBlur, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 })
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			shockBlur.Enabled = false
		end
	end)
	blurTween = tween
	tween:Play()
end

--- The shock front: a dome of rippling air racing out at SHOCK_SPEED, thinning as it
--- goes, with a skim of dust riding its foot. Returns how far it was drawn.
local function shockwave(host: BasePart, position: Vector3, r: number, order: number): number
	local reach = r * (SHOCK_REACH + math.max(0, order - GRAND_FROM) * 0.5)
	local duration = reach / SHOCK_SPEED

	-- ForceField draws as a refracting, shimmering shell -- the closest thing to a
	-- wall of compressed air the engine has. The ground hides its lower half.
	local dome = fxPart("Ball")
	dome.Material = Enum.Material.ForceField
	dome.Color = SHOCK_AIR
	dome.Size = Vector3.one * r * 0.4
	dome.CFrame = CFrame.new(position)
	dome.Parent = fxFolder
	TweenService:Create(dome, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.one * reach * 2,
	}):Play()
	TweenService:Create(dome, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	task.delay(duration + 0.1, function()
		dome:Destroy()
	end)

	-- Dust torn off the ground right at the front, moving WITH it -- no drag, so the
	-- ring of it stays on the dome's foot all the way out.
	local bearings = 20 + math.max(0, order - GRAND_FROM) * 4
	for index = 1, bearings do
		local angle = (index / bearings) * math.pi * 2
		local bearing = Instance.new("Attachment")
		bearing.CFrame = CFrame.new(0, 0.8, 0) * CFrame.Angles(0, angle, 0)
		bearing.Parent = host
		emitter(bearing, {
			Texture = TEX_SMOKE,
			EmissionDirection = Enum.NormalId.Front,
			Color = colours(0, SMOKE_PALE, 1, DUST),
			Size = seq(0, cap(r * 0.15), 1, cap(r * 0.45)),
			Transparency = seq(0, 0.45, 0.7, 0.6, 1, 1),
			Lifetime = NumberRange.new(duration * 0.85, duration),
			Speed = NumberRange.new(SHOCK_SPEED * 0.95, SHOCK_SPEED),
			SpreadAngle = Vector2.new(4, 2),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-60, 60),
		}):Emit(2)
	end

	return reach
end

--- The fireball, and what it becomes. One invisible ball carries it all: it swells and
--- climbs while fire boils on it (locked to it, so the fireball stays one body as it
--- lifts) around a sickly green heart. As the fire dies it rolls over into smoke.
--- Small nukes stop there: a lifting, darkening puff. Rare and up keep climbing on a
--- narrow stem and, at the top, throw a ring of smoke outward that curls down and back
--- in on itself -- the rolling cap -- lit from underneath by what is left of the fire.
local function fireballAndCloud(host: BasePart, position: Vector3, r: number, order: number)
	local g = grandeur(order)
	local column = order >= COLUMN_FROM
	local fullCap = order >= CAP_FROM
	local fr = r * 0.42 * g -- fireball radius
	local capRadius = r * g * (if fullCap then 0.8 else 0.5)
	local height = if fullCap then r * g * 2.7 elseif column then r * g * 1.7 else fr * 1.6
	local rise = if fullCap then 3.2 + (order - CAP_FROM) * 0.35 elseif column then 2.4 else 1.4
	local burn = if fullCap then 1.9 + (order - CAP_FROM) * 0.2 elseif column then 1.5 else 0.9

	local ball = fxPart("Ball")
	ball.Transparency = 1
	ball.Size = Vector3.one * fr * 0.8
	ball.CFrame = CFrame.new(position + Vector3.new(0, fr * 0.5, 0))
	ball.Parent = fxFolder

	local fire = emitter(ball, {
		Texture = TEX_FIRE,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		LockedToPart = true,
		Color = colours(0, FIRE_HOT, 0.35, FIRE_MID, 1, FIRE_DEEP),
		LightEmission = 1,
		Size = seq(0, cap(fr * 0.45), 0.5, cap(fr * 0.6), 1, cap(fr * 0.35)),
		Transparency = seq(0, 0.05, 0.6, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.45, 0.9),
		Speed = NumberRange.new(fr * 0.1, fr * 0.35),
		Drag = 2,
		Acceleration = Vector3.new(0, fr * 0.8, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-140, 140),
		Rate = 22 + order * 4,
	})

	-- Its body: soft, rolling billows of flame, so it reads as one boiling mass and
	-- not as a burst of spikes.
	local body = emitter(ball, {
		Texture = TEX_SMOKE,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		LockedToPart = true,
		Color = colours(0, FIRE_HOT, 0.4, FIRE_MID, 1, FIRE_DEEP),
		LightEmission = 0.8,
		Size = seq(0, cap(fr * 0.5), 1, cap(fr * 0.75)),
		Transparency = seq(0, 0.1, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(fr * 0.05, fr * 0.2),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-50, 50),
		Rate = 30 + order * 5,
	})

	-- THE RAD TINT: the heart of it burns green-white, drawn a little in front of the
	-- fire so it shows through as a core rather than a colour cast over everything.
	local heart = emitter(ball, {
		Texture = TEX_SMOKE,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		LockedToPart = true,
		Color = colours(0, RAD_WHITE, 0.3, RAD_GLOW, 1, RAD_HAZE),
		LightEmission = 0.15,
		Size = seq(0, cap(fr * 0.3), 1, cap(fr * 0.45)),
		Transparency = seq(0, 0.05, 0.6, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(0, fr * 0.1),
		ZOffset = fr * 0.6,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Rate = 20 + order * 4,
	})

	-- Smoke shed off the fireball's skin and left behind as it lifts: the broad, dirty
	-- base of the cloud.
	local shell = emitter(ball, {
		Texture = TEX_SMOKE,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Color = colours(0, SMOKE_LIT, 0.3, SMOKE, 1, SMOKE_PALE),
		LightEmission = 0.05,
		Size = seq(0, cap(fr * 0.55), 1, cap(fr * 1.0)),
		Transparency = seq(0, 0.35, 0.15, 0.2, 0.7, 0.45, 1, 1),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(fr * 0.05, fr * 0.15),
		Drag = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
	})

	local light = Instance.new("PointLight")
	light.Color = FIRE_MID:Lerp(RAD_GLOW, 0.25)
	light.Brightness = 2.5
	light.Range = math.min(60, fr * 2.2)
	light.Shadows = false
	light.Parent = ball
	TweenService:Create(light, TweenInfo.new(burn + 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Brightness = 0,
	}):Play()

	TweenService:Create(ball, TweenInfo.new(rise, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(position + Vector3.new(0, height, 0)),
		Size = Vector3.one * (if column then capRadius * 0.9 else fr * 1.2),
	}):Play()

	task.delay(burn * 0.4, function()
		shell.Rate = 10 + order * 2
	end)
	task.delay(burn * 0.7, function()
		heart.Enabled = false
	end)
	task.delay(burn, function()
		fire.Enabled = false
		body.Enabled = false
	end)
	-- A small one keeps shedding smoke as it lifts; a big one hands over to its stem.
	task.delay(if column then burn else rise + 0.6, function()
		shell.Enabled = false
	end)

	if column then
		-- The stem: much narrower than the head, drawn by the head climbing away from it.
		local stemAt = Instance.new("Attachment")
		stemAt.Parent = ball
		local stem = emitter(stemAt, {
			Texture = TEX_SMOKE,
			EmissionDirection = Enum.NormalId.Bottom,
			Color = colours(0, SMOKE_LIT, 0.3, SMOKE, 1, SMOKE_PALE),
			LightEmission = 0.05,
			Size = seq(0, cap(r * g * 0.2), 1, cap(r * g * 0.42)),
			Transparency = seq(0, 0.3, 0.7, 0.5, 1, 1),
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(20, 20),
			Drag = 1,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			Rate = 0,
		})

		-- The head: smoke that travels WITH the ball, so it climbs as one boiling mass
		-- instead of smearing into a second stem. Starts glowing, cools as it goes.
		local head = emitter(ball, {
			Texture = TEX_SMOKE,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			LockedToPart = true,
			Color = colours(0, SMOKE_LIT, 0.3, SMOKE_CAP, 1, SMOKE_CAP),
			LightEmission = 0.1,
			Size = seq(0, cap(capRadius * 0.5), 1, cap(capRadius * 0.8)),
			Transparency = seq(0, 1, 0.15, 0.3, 0.8, 0.4, 1, 1),
			Lifetime = NumberRange.new(1.4, 2.2),
			Speed = NumberRange.new(0.5, 2),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			Rate = 0,
		})

		-- What is left of the fire, still glowing through the underside of the cap.
		local underAt = Instance.new("Attachment")
		underAt.Position = Vector3.new(0, -capRadius * 0.45, 0)
		underAt.Parent = ball
		local underglow = emitter(underAt, {
			Texture = TEX_SMOKE,
			LockedToPart = true,
			Color = colours(0, RAD_HAZE, 1, RAD_HAZE),
			LightEmission = 0.3,
			Size = seq(0, cap(capRadius * 0.5), 1, cap(capRadius * 0.8)),
			Transparency = seq(0, 0.9, 0.4, 0.86, 1, 1),
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(0, 1),
			SpreadAngle = Vector2.new(180, 180),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			Rate = 0,
		})

		task.delay(burn * 0.5, function()
			head.Rate = 14 + order * 2
		end)
		task.delay(burn * 0.6, function()
			stem.Rate = 16 + order * 3
			underglow.Rate = 3 + order * 0.5
		end)

		task.delay(rise, function()
			stem.Enabled = false

			-- THE CAP: a ring of smoke thrown outward and up from the head, dragged
			-- back in and down as it goes -- the rolling edge of a real cap, which
			-- turns over on itself rather than just spreading.
			local ringCount = if fullCap then 12 else 8
			for index = 1, ringCount do
				local angle = (index / ringCount) * math.pi * 2
				local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local at = out * capRadius * 0.45
				local edge = Instance.new("Attachment")
				edge.CFrame = CFrame.lookAt(at, at + (out + Vector3.new(0, 0.55, 0)).Unit)
				edge.Parent = ball
				emitter(edge, {
					Texture = TEX_SMOKE,
					EmissionDirection = Enum.NormalId.Front,
					Color = colours(0, EMBER, 0.04, SMOKE_LIT, 0.18, SMOKE_CAP, 1, SMOKE_PALE),
					LightEmission = 0.1,
					Size = seq(0, cap(capRadius * 0.5), 1, cap(capRadius * 0.95)),
					Transparency = seq(0, 0.3, 0.7, 0.5, 1, 1),
					Lifetime = NumberRange.new(6, 9),
					Speed = NumberRange.new(capRadius * 0.45, capRadius * 0.7),
					SpreadAngle = Vector2.new(18, 18),
					Drag = 0.9,
					Acceleration = -out * capRadius * 0.06 + Vector3.new(0, -capRadius * 0.05, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-12, 12),
				}):Emit(if fullCap then 5 else 3)
			end

			-- The crown: the head's own smoke, let go to hang there once it tops out.
			emitter(ball, {
				Texture = TEX_SMOKE,
				Shape = Enum.ParticleEmitterShape.Sphere,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
				Color = colours(0, SMOKE_LIT, 0.3, SMOKE_CAP, 1, SMOKE_PALE),
				LightEmission = 0.05,
				Size = seq(0, cap(capRadius * 0.6), 1, cap(capRadius * 1.0)),
				Transparency = seq(0, 0.3, 0.7, 0.5, 1, 1),
				Lifetime = NumberRange.new(6, 9),
				Speed = NumberRange.new(capRadius * 0.08, capRadius * 0.18),
				Drag = 1,
				Acceleration = Vector3.new(0, capRadius * 0.02, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-12, 12),
			}):Emit(8 + order)
		end)
		task.delay(rise + 1.5, function()
			head.Enabled = false
		end)
		task.delay(rise + 2.5, function()
			underglow.Enabled = false
		end)

		if fullCap then
			-- The skirt: a thin pale collar condensing round the stem as the head
			-- punches up through the air above it.
			task.delay(rise * 0.55, function()
				local skirtHeight = height * 0.55
				local skirts = 10
				for index = 1, skirts do
					local angle = (index / skirts) * math.pi * 2
					local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
					local at = Vector3.new(0, skirtHeight, 0) + out * r * g * 0.2
					local collar = Instance.new("Attachment")
					collar.CFrame = CFrame.lookAt(at, at + out)
					collar.Parent = host
					emitter(collar, {
						Texture = TEX_SMOKE,
						EmissionDirection = Enum.NormalId.Front,
						Color = colours(0, SKIRT, 1, SMOKE_PALE),
						LightEmission = 0.15,
						Size = seq(0, cap(r * g * 0.2), 1, cap(r * g * 0.45)),
						Transparency = seq(0, 0.6, 0.5, 0.65, 1, 1),
						Lifetime = NumberRange.new(2.5, 3.5),
						Speed = NumberRange.new(r * g * 0.35, r * g * 0.5),
						SpreadAngle = Vector2.new(10, 4),
						Drag = 1.2,
						Rotation = NumberRange.new(0, 360),
						RotSpeed = NumberRange.new(-15, 15),
					}):Emit(2)
				end
			end)
		end
	end

	task.delay(rise + 11, function()
		ball:Destroy()
	end)

	return rise
end

local function blast(info: any)
	local position: Vector3 = info.position
	local blastRadius: number = info.blastRadius
	local order = rarityOrder(info.rarity)
	local r = blastRadius
	local g = grandeur(order)

	local host = fxPart()
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(position)
	host.Parent = fxFolder
	-- Lifted off the ground: a camera-facing sprite centred on the ground has its
	-- lower half sliced off by the floor behind it, which reads as a hard half-disc.
	local centre = Instance.new("Attachment")
	centre.Position = Vector3.new(0, r * 0.25, 0)
	centre.Parent = host

	-- THE FLASH: light, not a thing -- soft-edged, gone in a quarter of a second, a
	-- touch of radioactive green in its white.
	emitter(centre, {
		Texture = TEX_SMOKE,
		Color = colours(0, Color3.new(1, 1, 1), 1, FLASH_RAD),
		LightEmission = 1,
		Size = seq(0, cap(r * 0.8 * g), 1, cap(r * 1.5 * g)),
		Transparency = seq(0, 0, 0.5, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.18, 0.32),
		Speed = NumberRange.new(0, 0),
		ZOffset = r * 0.3,
		Rotation = NumberRange.new(0, 360),
	}):Emit(5)

	local light = Instance.new("PointLight")
	light.Color = FLASH
	light.Brightness = 3
	light.Range = math.min(60, r * 1.8)
	light.Shadows = false
	light.Parent = host
	TweenService:Create(light, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Color = FIRE_MID,
	}):Play()

	-- THE POP: the first instant of the fireball, flung out hard and braked by the air,
	-- with its smoke right behind it. The fireball proper takes over from here.
	emitter(centre, {
		Texture = TEX_FIRE,
		Color = colours(0, FIRE_HOT, 0.35, FIRE_MID, 1, FIRE_DEEP),
		LightEmission = 1,
		Size = seq(0, cap(r * 0.25), 0.4, cap(r * 0.45), 1, cap(r * 0.25)),
		Transparency = seq(0, 0, 0.6, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(r * 0.5, r * 1.1),
		ZOffset = r * 0.3,
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Acceleration = Vector3.new(0, r * 0.6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	}):Emit(26 + order * 3)

	emitter(centre, {
		Texture = TEX_SMOKE,
		Color = colours(0, SMOKE_LIT, 0.35, SMOKE, 1, SMOKE_PALE),
		LightEmission = 0.05,
		Size = seq(0, cap(r * 0.35), 1, cap(r * 0.9)),
		Transparency = seq(0, 0.15, 0.6, 0.45, 1, 1),
		Lifetime = NumberRange.new(2.5, 4.5),
		Speed = NumberRange.new(r * 0.25, r * 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.6,
		Acceleration = Vector3.new(0, r * 0.12, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
	}):Emit(18 + order * 3)

	-- THE PRESSURE RING: a flat disc of disturbed air skimming out along the ground.
	-- VelocityPerpendicular with a token upward speed lays the sprite flat.
	local ringAttachment = Instance.new("Attachment")
	ringAttachment.Position = Vector3.new(0, 0.35, 0)
	ringAttachment.Parent = host
	emitter(ringAttachment, {
		Texture = TEX_SMOKE,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Color = colours(0, FLASH, 1, SMOKE_PALE),
		LightEmission = 0.5,
		Size = seq(0, cap(r * 0.3), 1, cap(r * 3.2)),
		Transparency = seq(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.5),
		Speed = NumberRange.new(0.01, 0.01),
	}):Emit(1)

	-- THE DUST WAVE: the ground itself thrown outward in a ring, decelerating as it
	-- goes, well behind the shock front. One emitter per bearing, each pointing
	-- straight out (an emitter under an attachment fires along its own axes).
	local bearings = 14
	for index = 1, bearings do
		local angle = (index / bearings) * math.pi * 2
		local bearing = Instance.new("Attachment")
		bearing.CFrame = CFrame.new(0, 0.6, 0) * CFrame.Angles(0, angle, 0)
		bearing.Parent = host
		emitter(bearing, {
			Texture = TEX_SMOKE,
			EmissionDirection = Enum.NormalId.Front,
			Color = colours(0, DUST, 1, SMOKE_PALE),
			Size = seq(0, cap(r * 0.22 * g), 1, cap(r * 0.6 * g)),
			Transparency = seq(0, 0.3, 0.6, 0.5, 1, 1),
			Lifetime = NumberRange.new(1.3, 2.2 + (g - 1) * 2),
			Speed = NumberRange.new(r * 1.3, r * 1.9),
			SpreadAngle = Vector2.new(8, 8),
			Drag = 2.6,
			Acceleration = Vector3.new(0, 1.5, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
		}):Emit(3)
	end

	shockwave(host, position, r, order)
	local rise = fireballAndCloud(host, position, r, order)
	throwChunks(position, r, 8 + order * 2)

	-- THE BOOM. Deeper for bigger ones, carried a long way.
	local boom = Instance.new("Sound")
	boom.SoundId = BOOM_SOUND
	boom.Volume = math.min(3, 1 + order * 0.2)
	boom.PlaybackSpeed = math.max(0.55, 1.1 - order * 0.07)
	boom.RollOffMode = Enum.RollOffMode.InverseTapered
	boom.RollOffMinDistance = r * 2
	boom.RollOffMaxDistance = 900
	Sfx.adopt(boom) -- under Settings' SOUND EFFECTS switch
	boom.Parent = host
	boom:Play()
	if order >= CAP_FROM then
		-- A second, slower layer: the rumble that arrives under the crack.
		local rumble = boom:Clone()
		rumble.PlaybackSpeed = boom.PlaybackSpeed * 0.6
		rumble.Volume = boom.Volume * 0.8
		rumble.Parent = host
		rumble:Play()
	end

	task.delay(rise + 12, function()
		host:Destroy()
	end)

	-- What the CAMERA saw: the flash.
	local camera = Workspace.CurrentCamera
	if camera then
		local seen = (camera.CFrame.Position - position).Magnitude
		flashScene(math.clamp(1 - seen / (r * g * SCENE_FLASH_REACH), 0, 1) ^ 1.5)
	end

	-- What WE felt: the warm blast of heat up close, then the shock front arriving
	-- a beat later the farther away we were.
	local root = characterRoot()
	if root then
		local distance = (root.Position - position).Magnitude
		flashScreen(math.clamp(1 - distance / (r * FLASH_REACH), 0, 1) ^ 2)
		local felt = math.clamp(1 - distance / (r * g * SHAKE_REACH), 0, 1) ^ 1.2
		task.delay(distance / SHOCK_SPEED, shockHits, felt, order)
		if distance <= r then
			knockback(position, r)
		end
	end
end


-- ── 2. The crater ────────────────────────────────────────────────────────

type CraterFx = {
	marker: BasePart,
	folder: Folder,
	position: Vector3,
	radius: number,
	life: number,
	bornAt: number,
	orb: BasePart,
	haze: BasePart,
	light: PointLight,
	motes: ParticleEmitter,
	glows: { { emitter: ParticleEmitter, rate: number } },
	fissures: { BasePart },
	ground: { { part: BasePart, base: number } },
	rate: number,
}

local craters: { [BasePart]: CraterFx } = {}

local function buildCrater(marker: BasePart)
	if craters[marker] then
		return
	end
	local radius = marker:GetAttribute("OrbRadius")
	local life = marker:GetAttribute("OrbLife")
	local bornAt = marker:GetAttribute("BornAt")
	local rarity = marker:GetAttribute("Rarity")
	if typeof(radius) ~= "number" or typeof(life) ~= "number" or typeof(bornAt) ~= "number" then
		return
	end
	local order = rarityOrder(if typeof(rarity) == "string" then rarity else "Common")
	local position = marker.Position

	local folder = Instance.new("Folder")
	folder.Name = "Crater"
	folder.Parent = fxFolder

	local ground: { { part: BasePart, base: number } } = {}
	local function onGround(p: BasePart, transparency: number)
		p.Transparency = transparency
		p.Parent = folder
		table.insert(ground, { part = p, base = transparency })
	end

	-- Scorched ground, and a wider ring of ash round it. Flat cylinders, a hair proud
	-- of the floor and of each other so nothing z-fights.
	local ash = fxPart("Cylinder")
	ash.Material = Enum.Material.Slate
	ash.Color = ASH
	ash.Size = Vector3.new(0.1, radius * 2, radius * 2)
	ash.CFrame = CFrame.new(position + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	onGround(ash, 0.45)

	local scorch = fxPart("Cylinder")
	scorch.Material = Enum.Material.Slate
	scorch.Color = SCORCH
	scorch.Size = Vector3.new(0.12, radius * 1.35, radius * 1.35)
	scorch.CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	onGround(scorch, 0.05)

	-- The rim: the ground thrown up into one continuous berm round the hole, not a
	-- ring of loose blocks. Each bearing is a ridge of two wedges back to back -- a
	-- short steep face down into the crater, a long gentle one out onto the ash -- laid
	-- edge to edge so the slopes run on round the ring. Its height swells and dips on
	-- a slow wave, so neighbours never step against each other.
	local crest = radius * 0.7
	local inner = radius * 0.12
	local outer = radius * 0.24
	local bermHeight = radius * 0.09
	local bearings = 24
	local phase1, phase2 = math.random() * math.pi * 2, math.random() * math.pi * 2
	-- Wide enough to close the gap at the outer foot; the inner ends overlap instead.
	local bermWidth = 2 * (crest + outer) * math.sin(math.pi / bearings) * 1.05
	for index = 1, bearings do
		local angle = (index / bearings) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local h = bermHeight * (1 + 0.3 * math.sin(2 * angle + phase1) + 0.2 * math.sin(3 * angle + phase2))

		-- A WedgePart is full height on its Back (+Z) face and slopes down to its
		-- Front, so each wedge's Back faces the crest.
		local face = Instance.new("WedgePart")
		local back = Instance.new("WedgePart")
		for _, wedge in { face, back } do
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.CanQuery = false
			wedge.CanTouch = false
			wedge.CastShadow = false
			wedge.Material = Enum.Material.Slate
		end
		face.Color = SCORCH:Lerp(ASH, 0.35)
		face.Size = Vector3.new(bermWidth, h, inner)
		local faceAt = position + out * (crest - inner / 2) + Vector3.new(0, h / 2, 0)
		face.CFrame = CFrame.lookAt(faceAt, faceAt - out)
		onGround(face, 0)

		back.Color = ASH:Lerp(DUST, 0.25)
		back.Size = Vector3.new(bermWidth, h, outer)
		local backAt = position + out * (crest + outer / 2) + Vector3.new(0, h / 2, 0)
		back.CFrame = CFrame.lookAt(backAt, backAt + out)
		onGround(back, 0)
	end

	-- Shards thrown past the berm: small, low, lying where they landed.
	for _ = 1, 6 + order do
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local shard = Instance.new("WedgePart")
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Material = Enum.Material.Slate
		shard.Color = ASH:Lerp(DUST, math.random() * 0.6)
		local s = radius * (0.04 + math.random() * 0.04)
		shard.Size = Vector3.new(s * (0.8 + math.random() * 0.6), s * 0.35, s * (1 + math.random() * 0.8))
		local at = position + out * radius * (0.95 + math.random() * 0.2) + Vector3.new(0, shard.Size.Y / 2, 0)
		shard.CFrame = CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		onGround(shard, 0)
	end

	-- Fissures: the ground split open and glowing. Each crack wanders -- a few short
	-- segments, each turned a little off the last -- and narrows as it goes, starting
	-- clear of the centre rather than spoking out of one point. Some fork. A dim green,
	-- not RAD_GLOW: at full brightness Neon blooms into flat yellow lines. OPAQUE, and
	-- dimmed by colour as the crater cools (stepCraters): a transparent part writes no
	-- depth, so the glow sprites over the crater floor washed the far cracks out.
	local fissures: { BasePart } = {}
	local glows: { { emitter: ParticleEmitter, rate: number } } = {}
	local function crack(from: Vector3, heading: number, length: number, width: number, depth: number)
		local segments = 3 + math.random(0, 1)
		local at = from
		for index = 1, segments do
			heading += (math.random() - 0.5) * 0.9
			local step = length / segments * (0.7 + math.random() * 0.6)
			local w = width * (1 - (index - 1) / segments * 0.7)
			local direction = Vector3.new(math.cos(heading), 0, math.sin(heading))
			local to = at + direction * step
			local mid = (at + to) / 2
			local segment = fxPart()
			segment.Material = Enum.Material.Neon
			segment.Color = CRACK_GLOW
			-- Long by a width at each end, so the joints overlap instead of gapping.
			segment.Size = Vector3.new(w, 0.06, step + w)
			segment.CFrame = CFrame.lookAt(mid, mid + direction) + Vector3.new(0, 0.14, 0)
			segment.Parent = folder
			table.insert(fissures, segment)

			-- Every other segment leaks a thread of green vapour along its length.
			if index % 2 == 1 then
				local vapour = emitter(segment, {
					Texture = TEX_SMOKE,
					Color = colours(0, RAD_HAZE, 1, SMOKE_PALE),
					LightEmission = 0.3,
					Size = seq(0, 0.6, 1, 2.2),
					Transparency = seq(0, 0.8, 0.5, 0.85, 1, 1),
					Lifetime = NumberRange.new(1.8, 3),
					Speed = NumberRange.new(0.8, 1.8),
					SpreadAngle = Vector2.new(10, 10),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-20, 20),
					Rate = 0.8,
				})
				table.insert(glows, { emitter = vapour, rate = 0.8 })
			end

			if depth > 0 and index == 2 and math.random() < 0.5 then
				crack(to, heading + (if math.random() < 0.5 then 0.7 else -0.7), length * 0.45, w * 0.8, depth - 1)
			end
			at = to
		end
	end
	local count = 6 + math.floor(order / 2)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + (math.random() - 0.5) * 0.6
		local start = position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * (0.12 + math.random() * 0.06)
		crack(start, angle, radius * (0.3 + math.random() * 0.3), 0.45 + math.random() * 0.2, 1)
	end

	-- THE ORB. A ForceField-material shell reads as a shimmer of hot air rather than a
	-- solid; a faint haze just inside it gives it a body; light pooled on the
	-- ground lights it from within.
	local orb = fxPart("Ball")
	orb.Material = Enum.Material.ForceField
	orb.Color = RAD_AIR
	orb.Size = Vector3.one * radius * 2
	orb.CFrame = CFrame.new(position)
	orb.Parent = folder

	local haze = fxPart("Ball")
	haze.Color = RAD_HAZE
	haze.Transparency = 0.9
	haze.Size = Vector3.one * radius * 1.94
	haze.CFrame = CFrame.new(position)
	haze.Parent = folder

	-- The hot centre: light pooled on the crater floor and a slow rising glow, not a
	-- solid ball. The pool is a sprite laid flat (VelocityPerpendicular with a token
	-- upward speed), soft-edged, breathing as new ones replace old. Heights: scorch top
	-- 0.13, pool 0.15, fissure tops 0.17 -- above the scorch, under the cracks.
	local core = fxPart()
	core.Transparency = 1
	core.Size = Vector3.one
	core.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0))
	core.Parent = folder

	local pool = emitter(core, {
		Texture = TEX_SMOKE,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Color = colours(0, RAD_GLOW, 1, RAD_HAZE),
		LightEmission = 1,
		Size = seq(0, cap(radius * 0.4), 1, cap(radius * 0.55)),
		Transparency = seq(0, 1, 0.3, 0.55, 0.7, 0.6, 1, 1),
		Lifetime = NumberRange.new(1.6, 2.4),
		Speed = NumberRange.new(0.01, 0.01),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8),
		Rate = 2.5,
	})
	table.insert(glows, { emitter = pool, rate = 2.5 })

	local rising = emitter(core, {
		Texture = TEX_SMOKE,
		Color = colours(0, RAD_GLOW, 0.5, RAD_HAZE, 1, SMOKE_PALE),
		LightEmission = 0.6,
		Size = seq(0, cap(radius * 0.12), 1, cap(radius * 0.3)),
		Transparency = seq(0, 1, 0.2, 0.7, 1, 1),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(15, 15),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
		Rate = 3,
	})
	table.insert(glows, { emitter = rising, rate = 3 })

	local light = Instance.new("PointLight")
	light.Color = RAD_GLOW
	light.Brightness = 2.5
	light.Range = math.min(60, radius * 1.6)
	light.Shadows = false
	light.Parent = core

	local rate = math.clamp(radius * radius * 0.12, 10, 110)
	local motes = emitter(orb, {
		Texture = TEX_SPARKLE,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = colours(0, RAD_GLOW, 1, RAD_AIR),
		LightEmission = 1,
		Size = seq(0, 0.2, 0.5, 0.55, 1, 0),
		Transparency = seq(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(0.3, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 1.2, 0),
		Rate = rate,
	})

	craters[marker] = {
		marker = marker,
		folder = folder,
		position = position,
		radius = radius,
		life = life,
		bornAt = bornAt,
		orb = orb,
		haze = haze,
		light = light,
		motes = motes,
		glows = glows,
		fissures = fissures,
		ground = ground,
		rate = rate,
	}
end

local function dropCrater(marker: BasePart)
	local fx = craters[marker]
	if fx then
		fx.folder:Destroy()
		craters[marker] = nil
	end
end

local tint: ColorCorrectionEffect = nil :: any

local function stepCraters(now: number, clock: number)
	local root = characterRoot()
	local inside = 0

	for marker, fx in craters do
		if marker.Parent == nil then
			dropCrater(marker)
			continue
		end

		local strength = Detonation.orbStrength(now - fx.bornAt, fx.life)
		local radius = Detonation.orbRadiusAt(fx.radius, strength)
		local breathe = 1 + 0.03 * math.sin(clock * 4.2 + fx.bornAt)

		fx.orb.Size = Vector3.one * math.max(0.05, radius * 2 * breathe)
		fx.haze.Size = Vector3.one * math.max(0.05, radius * 1.94 * breathe)
		fx.orb.Transparency = if strength <= 0 then 1 else 0
		fx.haze.Transparency = 1 - 0.1 * strength
		fx.light.Brightness = 2.5 * strength * (0.85 + 0.15 * math.sin(clock * 6))
		fx.motes.Rate = fx.rate * strength
		for _, glow in fx.glows do
			glow.emitter.Rate = glow.rate * strength
		end
		-- The scorch outlives the heat a little, then goes with the marker. The cracks
		-- cool from glowing green to dark as the heat goes, and fade out WITH the scorch
		-- -- opaque until then, see buildCrater -- or they are left as black lines on
		-- bare ground.
		local fade = math.clamp(1 - strength * 1.5, 0, 1)
		for _, entry in fx.ground do
			entry.part.Transparency = entry.base + (1 - entry.base) * fade
		end
		for _, fissure in fx.fissures do
			local heat = strength * (0.8 + 0.2 * math.sin(clock * 3 + fissure.Size.Z * 2))
			fissure.Color = SCORCH:Lerp(CRACK_GLOW, heat)
			fissure.Transparency = fade
		end

		if root and radius > 0 then
			local distance = (root.Position - fx.position).Magnitude
			if distance < radius then
				inside = math.max(inside, 1 - distance / radius)
			end
		end
	end

	-- Inside the orb, the whole world goes green. The HUD's burn overlay already says
	-- you are being hurt (ExposureService folds the crater into healthBurn); this says
	-- WHY, without a word on screen.
	local amount = math.clamp(inside * 1.5, 0, 1) * TINT_MAX
	tint.TintColor = Color3.new(1, 1, 1):Lerp(TINT_INSIDE, amount / TINT_MAX * 0.9)
	tint.Saturation = -0.15 * amount / TINT_MAX
	tint.Enabled = amount > 0.001
end

-- ── 3. The fuse ──────────────────────────────────────────────────────────

type FuseFx = {
	instance: Instance,
	role: string,
	anchor: Part?,
	light: PointLight?,
	tick: Sound?,
	board: BillboardGui?,
	label: TextLabel?,
	highlight: Highlight?,
	nextTick: number,
	armedSpan: number?,
}

local fuses: { [Instance]: FuseFx } = {}

local function pivotOf(instance: Instance): Vector3?
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

local function trackFuse(instance: Instance)
	if fuses[instance] then
		return
	end
	local role = instance:GetAttribute(DetonationConfig.ATTR_ROLE)
	-- A dropped bomb (Services/BombService) is both at once: a nuke you can see glowing,
	-- and a spot on the ground that ticks and counts down.
	local fx: FuseFx = {
		instance = instance,
		role = if role == "lump" or role == "bomb" then role else "spot",
		nextTick = 0,
	}

	if fx.role == "lump" or fx.role == "bomb" then
		-- The nuke itself glowing through its crust as it heats. A Highlight rather
		-- than recolouring the lump: the lump is a replicated server model, and the
		-- crust's colour is the rarity's.
		local highlight = Instance.new("Highlight")
		highlight.Adornee = instance
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = FUSE_WARM
		highlight.FillTransparency = 1
		highlight.OutlineColor = FUSE_ARMED
		highlight.OutlineTransparency = 1
		highlight.Parent = fxFolder
		fx.highlight = highlight
	end
	if fx.role ~= "lump" then
		-- The spot: a local anchor over it carrying the warning light, the tick and the
		-- countdown, so nothing is parented into the replicated aura.
		local anchor = fxPart()
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.Parent = fxFolder
		fx.anchor = anchor

		local light = Instance.new("PointLight")
		light.Color = FUSE_WARM
		light.Brightness = 0
		light.Range = 14
		light.Shadows = false
		light.Parent = anchor
		fx.light = light

		local tick = Instance.new("Sound")
		tick.SoundId = TICK_SOUND
		tick.Volume = 0.9
		tick.RollOffMode = Enum.RollOffMode.InverseTapered
		tick.RollOffMinDistance = 8
		tick.RollOffMaxDistance = 90
		Sfx.adopt(tick)
		tick.Parent = anchor
		fx.tick = tick

		local board = Instance.new("BillboardGui")
		board.Name = "FuseCountdown"
		board.Adornee = anchor
		board.Size = UDim2.fromOffset(140, 48)
		board.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
		board.MaxDistance = 160
		board.LightInfluence = 0
		board.Enabled = false
		board.Parent = fxFolder
		fx.board = board
		fx.label = UIKit.label(board, {
			name = "Seconds",
			size = UDim2.fromScale(1, 1),
			font = UIKit.Font.hero,
			textSize = 36,
			color = FUSE_ARMED,
			xAlign = Enum.TextXAlignment.Center,
		})
	end

	fuses[instance] = fx
end

local function untrackFuse(instance: Instance)
	local fx = fuses[instance]
	if fx == nil then
		return
	end
	for _, thing in { fx.anchor, fx.board, fx.highlight } :: { Instance? } do
		if thing then
			thing:Destroy()
		end
	end
	fuses[instance] = nil
end

local function stepFuses(now: number, clock: number)
	local warnAt = DetonationConfig.WARN_AT
	local armAt = DetonationConfig.ARM_AT

	for instance, fx in fuses do
		if instance.Parent == nil or not CollectionService:HasTag(instance, DetonationConfig.HOT_TAG) then
			untrackFuse(instance)
			continue
		end

		local heatValue = instance:GetAttribute(DetonationConfig.ATTR_HEAT)
		local heat = if typeof(heatValue) == "number" then heatValue else 0
		local armed = instance:GetAttribute(DetonationConfig.ATTR_ARMED) == true
		local blowsAtValue = instance:GetAttribute(DetonationConfig.ATTR_BLOWS_AT)
		local left = if armed and typeof(blowsAtValue) == "number" then math.max(0, blowsAtValue - now) else nil
		local warmth = math.clamp((heat - warnAt) / (armAt - warnAt), 0, 1)
		local flash = 0.5 + 0.5 * math.sin(clock * (if armed then 14 else 5))

		if armed and fx.armedSpan == nil and left then
			fx.armedSpan = math.max(left, 0.1)
		end

		if fx.highlight then
			local highlight = fx.highlight
			if armed then
				highlight.FillColor = FUSE_ARMED
				highlight.FillTransparency = 0.25 + 0.3 * flash
				highlight.OutlineTransparency = 0.2
			else
				highlight.FillColor = FUSE_WARM
				highlight.FillTransparency = 1 - 0.4 * warmth
				highlight.OutlineTransparency = 1
			end
		end

		local anchor = fx.anchor
		if anchor then
			local at = pivotOf(instance)
			if at then
				anchor.CFrame = CFrame.new(at + Vector3.new(0, 1.2, 0))
			end
			local light = fx.light :: PointLight
			if armed then
				light.Color = FUSE_ARMED
				light.Brightness = 2 + 4 * flash
			else
				light.Color = FUSE_WARM
				light.Brightness = 3 * warmth * (0.7 + 0.3 * flash)
			end

			-- The tick: nothing while it is cool, a slow tick once it is worth noticing,
			-- then faster and faster through the armed seconds.
			local interval: number? = nil
			if armed then
				local span = fx.armedSpan or 1
				local through = if left then 1 - math.clamp(left / span, 0, 1) else 1
				interval = BEEP_ARMED_SLOW + (BEEP_ARMED_FAST - BEEP_ARMED_SLOW) * through
			elseif heat >= warnAt then
				interval = BEEP_WARN_INTERVAL
			end
			if interval and clock >= fx.nextTick then
				local tick = fx.tick :: Sound
				tick.PlaybackSpeed = if armed then 1.6 else 1.1
				tick:Play()
				fx.nextTick = clock + interval
			end

			local board = fx.board :: BillboardGui
			board.Enabled = armed and left ~= nil
			if armed and left and fx.label then
				fx.label.Text = string.format("%.1f", left)
				fx.label.TextColor3 = FUSE_ARMED:Lerp(Color3.fromHex("FFD2C4"), flash * 0.5)
			end
		end
	end
end

-- ── Lifecycle ────────────────────────────────────────────────────────

--- The shock's punch on the FOV: snapped wide, eased back. Rides on whatever FOV the
--- camera already had, and if something else changes it mid-kick (the wash bay's
--- zoom) theirs becomes the base -- we never restore a stale value over it.
local function stepFovKick(camera: Camera, clock: number)
	local kick = 0
	for index = #fovKicks, 1, -1 do
		local k = fovKicks[index]
		local t = (clock - k.t0) / k.duration
		if t >= 1 then
			table.remove(fovKicks, index)
		else
			local envelope = if t < 0.12 then t / 0.12 else (1 - (t - 0.12) / 0.88) ^ 2
			kick += k.amp * envelope
		end
	end

	if fovApplied ~= nil and math.abs(camera.FieldOfView - fovApplied) > 0.01 then
		fovBase = nil
		fovApplied = nil
	end
	if kick > 0.01 then
		local base = fovBase or camera.FieldOfView
		fovBase = base
		camera.FieldOfView = math.clamp(base + kick, 1, 120)
		fovApplied = camera.FieldOfView
	elseif fovBase ~= nil then
		if fovApplied ~= nil then
			camera.FieldOfView = fovBase
		end
		fovBase = nil
		fovApplied = nil
	end
end

function DetonationController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "DetonationFx"
	fxFolder.Parent = Workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "DetonationFlash"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None -- the flash is the whole screen, notch and all
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	screenFlash = Instance.new("Frame")
	screenFlash.Name = "Flash"
	screenFlash.Size = UDim2.fromScale(1, 1)
	screenFlash.BackgroundColor3 = SCREEN_FLASH
	screenFlash.BackgroundTransparency = 1
	screenFlash.BorderSizePixel = 0
	screenFlash.Visible = false
	screenFlash.Parent = gui

	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "CraterTint"
	tint.Enabled = false
	tint.Parent = Lighting

	sceneFlash = Instance.new("ColorCorrectionEffect")
	sceneFlash.Name = "BlastFlash"
	sceneFlash.Enabled = false
	sceneFlash.Parent = Lighting

	shockBlur = Instance.new("BlurEffect")
	shockBlur.Name = "BlastShockBlur"
	shockBlur.Size = 0
	shockBlur.Enabled = false
	shockBlur.Parent = Lighting

	Net.get("Detonation").OnClientEvent:Connect(function(info)
		local ok, err = pcall(blast, info)
		if not ok then
			warn(`[boom] blast fx failed: {err}`)
		end
	end)

	-- Craters: whatever is already burning when we arrive, and every new one.
	local function watchCraters(folder: Instance)
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				buildCrater(child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				buildCrater(child)
			end
		end)
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("BasePart") then
				dropCrater(child)
			end
		end)
	end
	local existing = Workspace:FindFirstChild(DetonationConfig.FOLDER)
	if existing then
		watchCraters(existing)
	else
		local connection: RBXScriptConnection? = nil
		connection = Workspace.ChildAdded:Connect(function(child)
			if child.Name == DetonationConfig.FOLDER and child:IsA("Folder") then
				(connection :: RBXScriptConnection):Disconnect()
				watchCraters(child)
			end
		end)
	end

	for _, instance in CollectionService:GetTagged(DetonationConfig.HOT_TAG) do
		trackFuse(instance)
	end
	CollectionService:GetInstanceAddedSignal(DetonationConfig.HOT_TAG):Connect(trackFuse)
	CollectionService:GetInstanceRemovedSignal(DetonationConfig.HOT_TAG):Connect(untrackFuse)

	-- Camera shake and the shock's FOV kick, after the camera has had its turn so they
	-- are an offset on this frame's view rather than a fight with the camera script.
	RunService:BindToRenderStep("DetonationShake", Enum.RenderPriority.Camera.Value + 2, function()
		local camera = Workspace.CurrentCamera
		local clock = os.clock()
		if camera and (#fovKicks > 0 or fovBase ~= nil) then
			stepFovKick(camera, clock)
		end
		if #shakes == 0 then
			return
		end
		local total = 0
		for index = #shakes, 1, -1 do
			local s = shakes[index]
			local t = (clock - s.t0) / s.duration
			if t >= 1 then
				table.remove(shakes, index)
			else
				total += s.amp * (1 - t) ^ 2
			end
		end
		if total > 0 and camera then
			local rx = math.noise(clock * 22, 0.37) * total
			local ry = math.noise(0.71, clock * 22) * total
			local rz = math.noise(clock * 15, clock * 9) * total * 0.4
			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local clock = os.clock()

		-- Thrown chunks: a hand-flown arc, then a moment on the ground, then gone.
		for index = #chunks, 1, -1 do
			local chunk = chunks[index]
			local t = clock - chunk.t0
			if chunk.landed then
				local since = clock - chunk.landed
				chunk.part.Transparency = math.clamp((since - 1.2) / 0.8, 0, 1)
				if since >= 2 then
					chunk.part:Destroy()
					table.remove(chunks, index)
				end
			else
				local at = chunk.from + chunk.velocity * t + Vector3.new(0, -0.5 * GRAVITY * t * t, 0)
				if at.Y <= chunk.floor and t > 0.1 then
					at = Vector3.new(at.X, chunk.floor, at.Z)
					chunk.landed = clock
				end
				chunk.part.CFrame = CFrame.new(at) * CFrame.Angles(chunk.spin.X * t, chunk.spin.Y * t, chunk.spin.Z * t)
			end
		end

		stepCraters(now, clock)
		stepFuses(now, clock)
	end)
end

return DetonationController
