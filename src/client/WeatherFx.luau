--!strict
--[[
	WeatherFx.luau — what Golden Hour and the Meteor Shower look like in the air
	(Config/Weather). AtmosphereController repaints the sky; this adds what moves in
	it. WeatherController switches each one on and off.

	CLIENT-ONLY, like AuroraFx: nothing here replicates, and it all follows the local
	camera, so it costs the server nothing and a player only ever draws their own.

	  GOLDEN DUST     warm motes drifting round the camera, out of a flat sheet that
	                  rides above it (the aurora's sparkle trick, in gold).
	  SHOOTING STARS  short streaks across the top of the view every STREAK_GAP_*
	                  seconds -- the shower's backdrop, not the meteors that land.
	  METEORS         `fall(position, landsAt)`: a fireball out of the sky that hits
	                  `position` at `landsAt`, then a flash, sparks, smoke and a boom
	                  there. The spot it plants is DigService's aura, drawn by
	                  FieldController; this is only the arrival.

	NO TEXTURE ASSETS beyond the engine's own particle textures, and nothing Neon but
	the fireball's core (it IS a light source; the Neon note in Config/Items).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Sfx = require(script.Parent.Sfx)

local WeatherFx = {}

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local BOOM_SOUND = "rbxasset://sounds/impact_explosion_03.mp3"

local GOLD = Color3.fromHex("FFD36B")
local AMBER = Color3.fromHex("FF9F3A")
local FIRE = Color3.fromHex("FF8A2A")
local HOT = Color3.fromHex("FFE6B0")

local DUST_HEIGHT = 30
local DUST_RATE = 22
local FADE = 4 -- seconds for the dust and the streaks to come up or die away

local STREAK_GAP_MIN = 0.5
local STREAK_GAP_MAX = 1.6

-- Where a landing meteor comes in from: up and off to one side, far enough out that
-- it reads as coming from the sky rather than from the next field over.
local FALL_FROM = Vector3.new(-0.55, 1, 0.35).Unit * 420

local folder: Folder? = nil
local function fxFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "WeatherFx"
	made.Parent = Workspace
	folder = made
	return made
end

local function ghostPart(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- ── Golden dust ───────────────────────────────────────────────────────────

local dustSource: Part? = nil
local dust: ParticleEmitter? = nil
local dustTarget, dustLevel = 0, 0

local function buildDust()
	local source = ghostPart("GoldenDust", Vector3.new(120, 1, 120), fxFolder())
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(GOLD, AMBER)
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(6, 9)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0.6, -1.2, 0.3)
	emitter.Drag = 0.4
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Rate = 0
	emitter.Parent = source
	dustSource = source
	dust = emitter
end

-- ── Shooting stars ────────────────────────────────────────────────────────

local streakTarget, streakLevel = 0, 0
local nextStreak = 0

--- One streak across the top of the view: a beam whose head runs along `dir` and
--- whose tail chases it, fading out over its short life.
local function streak(camera: Camera)
	local look = camera.CFrame.LookVector
	local bearing = math.atan2(look.X, look.Z) + (math.random() - 0.5) * math.rad(140)
	-- Measured: at ~400 studs a streak was a hair-thin line the haze ate. Nearer and
	-- wider reads as a shooting star against the shower's night.
	local distance = 170 + math.random() * 110
	local at = camera.CFrame.Position
	local start = at
		+ Vector3.new(math.sin(bearing) * distance, 70 + math.random() * 90, math.cos(bearing) * distance)
	local across = Vector3.new(math.cos(bearing), 0, -math.sin(bearing)) * (if math.random() < 0.5 then 1 else -1)
	local dir = (across + Vector3.new(0, -0.35 - math.random() * 0.3, 0)).Unit
	local length = 90 + math.random() * 70
	local life = 0.7 + math.random() * 0.5

	local part = ghostPart("Streak", Vector3.one, fxFolder())
	part.CFrame = CFrame.new(start)
	local tail = Instance.new("Attachment")
	tail.Parent = part
	local head = Instance.new("Attachment")
	head.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment0 = tail
	beam.Attachment1 = head
	beam.FaceCamera = true
	beam.Width0 = 0
	beam.Width1 = 4
	beam.Color = ColorSequence.new(Color3.fromHex("9FB4FF"), Color3.new(1, 1, 1))
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 1
	beam.Parent = part

	local born = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - born) / life
		if t >= 1 then
			connection:Disconnect()
			part:Destroy()
			return
		end
		local travelled = t * length * 2.2
		head.Position = dir * travelled
		tail.Position = dir * math.max(0, travelled - length * math.min(1, t * 3))
		-- In quickly, out slowly, and dimmer while the shower fades in or out.
		local shown = if t < 0.15 then t / 0.15 else 1 - (t - 0.15) / 0.85
		beam.Transparency = NumberSequence.new(1 - math.clamp(shown, 0, 1) * streakLevel * 0.9)
	end)
end

-- ── Landing meteors ───────────────────────────────────────────────────────

local function impact(position: Vector3)
	local root = ghostPart("MeteorImpact", Vector3.one, fxFolder())
	root.CFrame = CFrame.new(position + Vector3.yAxis)

	local flash = Instance.new("PointLight")
	flash.Color = FIRE
	flash.Range = 45
	flash.Brightness = 8
	flash.Shadows = false
	flash.Parent = root

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = FIRE_TEXTURE
	sparks.Color = ColorSequence.new(HOT, FIRE)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0, 1)
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(25, 50)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Rate = 0
	sparks.Parent = root
	sparks:Emit(45)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(Color3.fromHex("6B5A4A"), Color3.fromHex("2E2A28"))
	smoke.LightInfluence = 1
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(2.5, 4)
	smoke.Speed = NumberRange.new(6, 14)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Drag = 1.5
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Rate = 0
	smoke.Parent = root
	smoke:Emit(18)

	local boom = Instance.new("Sound")
	boom.SoundId = BOOM_SOUND
	boom.Volume = 0.9
	boom.RollOffMode = Enum.RollOffMode.InverseTapered
	boom.RollOffMinDistance = 30
	boom.RollOffMaxDistance = 600
	boom.Parent = root
	Sfx.adopt(boom, "sfx")
	boom:Play()

	local born = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - born) / 0.8
		flash.Brightness = 8 * math.max(0, 1 - t)
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	Debris:AddItem(root, 6)
end

--- A meteor out of the sky, landing on `position` at `landsAt` (server time).
function WeatherFx.fall(position: Vector3, landsAt: number)
	local duration = math.clamp(landsAt - Workspace:GetServerTimeNow(), 0.2, 4)
	local from = position + FALL_FROM

	local ball = Instance.new("Part")
	ball.Name = "Meteor"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(5, 5, 5)
	ball.Material = Enum.Material.Neon
	ball.Color = FIRE
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.CFrame = CFrame.new(from)
	ball.Parent = fxFolder()

	local glow = Instance.new("PointLight")
	glow.Color = FIRE
	glow.Range = 30
	glow.Brightness = 4
	glow.Parent = ball

	-- The fiery tail: a trail between two points across the ball.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 2, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(HOT, FIRE)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = ball

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(Color3.fromHex("8A6A50"))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Speed = NumberRange.new(0)
	smoke.Rate = 40
	smoke.LockedToPart = false
	smoke.Parent = ball

	local born = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - born) / duration)
		-- Speeding up as it comes in.
		local eased = t * t
		ball.CFrame = CFrame.new(from:Lerp(position, eased))
		if t >= 1 then
			connection:Disconnect()
			smoke.Rate = 0
			ball.Transparency = 1
			glow.Enabled = false
			Debris:AddItem(ball, 2)
			impact(position)
		end
	end)
end

-- ── The switch ────────────────────────────────────────────────────────────

local connection: RBXScriptConnection? = nil

local function step(dt: number)
	dustLevel = if dustTarget > dustLevel then math.min(dustTarget, dustLevel + dt / FADE) else math.max(dustTarget, dustLevel - dt / FADE)
	streakLevel = if streakTarget > streakLevel
		then math.min(streakTarget, streakLevel + dt / FADE)
		else math.max(streakTarget, streakLevel - dt / FADE)

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local at = camera.CFrame.Position

	if dustSource and dust then
		dustSource.CFrame = CFrame.new(at.X, at.Y + DUST_HEIGHT, at.Z)
		dust.Rate = DUST_RATE * dustLevel
	end

	if streakLevel > 0 then
		local now = os.clock()
		if now >= nextStreak then
			nextStreak = now + (STREAK_GAP_MIN + math.random() * (STREAK_GAP_MAX - STREAK_GAP_MIN)) / math.max(0.25, streakLevel)
			streak(camera)
		end
	end

	if dustLevel <= 0 and dustTarget <= 0 and streakLevel <= 0 and streakTarget <= 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function wake()
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
end

--- Golden Hour's dust on (true) or off (false), fading either way. Idempotent.
function WeatherFx.setGolden(on: boolean)
	dustTarget = if on then 1 else 0
	if on and dust == nil then
		buildDust()
	end
	if on or dustLevel > 0 then
		wake()
	end
end

--- The Meteor Shower's shooting stars on or off, fading either way. Idempotent.
function WeatherFx.setMeteors(on: boolean)
	streakTarget = if on then 1 else 0
	if on or streakLevel > 0 then
		wake()
	end
end

return WeatherFx
