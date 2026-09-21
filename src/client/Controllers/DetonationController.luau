--!strict
--[[
	DetonationController.luau — what a nuke going off looks like, and what it leaves.

	THREE JOBS, all driven by the server and all purely visual except one:

	  1. THE BLAST (the Detonation remote, fired to every client). A flash, a fireball
	     that rolls straight into smoke, a pressure ring skimming the ground, a wave of
	     dust thrown outward, chunks of ground flung and falling back, and for the rare
	     ones a column of smoke that climbs and -- Epic and up -- spreads into a cap.
	     The boom, the camera shake and a warm screen flash scale with how close you
	     were. THE ONE NON-VISUAL THING: if YOUR character was inside the blast, this
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
local DUST = Color3.fromHex("6E6456")
local CHUNK = Color3.fromHex("2B2621")
local SCORCH = Color3.fromHex("1C1814")
local ASH = Color3.fromHex("3A332B")
local RAD_GLOW = Color3.fromHex("A6FF3E") -- fissures and the orb's heart
local RAD_AIR = Color3.fromHex("8CFF4A") -- the orb's shell
local RAD_HAZE = Color3.fromHex("5ED62A")
local SCREEN_FLASH = Color3.fromHex("FFE6B8") -- warm; the white screen means suit failure
local TINT_INSIDE = Color3.fromHex("C9FFB0")
local FUSE_WARM = Color3.fromHex("F59E0B")
local FUSE_ARMED = Color3.fromHex("FF2A1A")

-- ── Tuning (visual only) ────────────────────────────────────────────────
local COLUMN_FROM = 4 -- Rarity order: Rare and up throw a smoke column
local CAP_FROM = 5 -- Epic and up spread it into a mushroom cap
local SHAKE_REACH = 8 -- shake is felt out to this many blast radii
local FLASH_REACH = 6 -- the screen flash, out to this many blast radii
local GRAVITY = 70 -- studs/s^2 for thrown chunks; a touch floatier than Workspace's
local BEEP_WARN_INTERVAL = 0.9
local BEEP_ARMED_SLOW = 0.45
local BEEP_ARMED_FAST = 0.08
local TINT_MAX = 0.55

local player = Players.LocalPlayer

local fxFolder: Folder = nil :: any
local shakes: { { amp: number, t0: number, duration: number } } = {}

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

--- The smoke column, and for the biggest ones the cap: a smoke source that climbs out
--- of the fireball and leaves its trail standing behind it, then bursts outward and
--- rolls when it tops out. Particles stay where they were emitted, so the stem draws
--- itself as the source rises.
local function raiseCloud(position: Vector3, blastRadius: number, withCap: boolean)
	local height = blastRadius * (if withCap then 2.8 else 1.6)
	local rise = if withCap then 3.4 else 2.2

	local riser = fxPart()
	riser.Transparency = 1
	riser.Size = Vector3.one
	riser.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	riser.Parent = fxFolder

	local stem = emitter(riser, {
		Texture = TEX_SMOKE,
		Color = colours(0, SMOKE_LIT, 0.25, SMOKE, 1, SMOKE_PALE),
		LightEmission = 0.05,
		Size = seq(0, cap(blastRadius * 0.28), 1, cap(blastRadius * 0.6)),
		Transparency = seq(0, 0.25, 0.7, 0.45, 1, 1),
		Lifetime = NumberRange.new(5, 7.5),
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(25, 25),
		Drag = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		Rate = 14 + blastRadius * 0.6,
	})

	-- Fire still feeding the bottom of the column for its first second.
	local ember = emitter(riser, {
		Texture = TEX_FIRE,
		Color = colours(0, FIRE_HOT, 0.5, FIRE_MID, 1, FIRE_DEEP),
		LightEmission = 1,
		Size = seq(0, cap(blastRadius * 0.3), 1, cap(blastRadius * 0.1)),
		Transparency = seq(0, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(30, 30),
		Rate = 20,
	})
	task.delay(1.1, function()
		ember.Enabled = false
	end)

	TweenService:Create(riser, TweenInfo.new(rise, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(position + Vector3.new(0, height, 0)),
	}):Play()

	task.delay(rise, function()
		stem.Enabled = false
		if withCap then
			-- The cap: a burst thrown outward and a little down from the top of the
			-- column, big and slow, so it spreads into a rolling flat head.
			local head = emitter(riser, {
				Texture = TEX_SMOKE,
				Color = colours(0, SMOKE_LIT, 0.25, SMOKE_CAP, 1, SMOKE_PALE),
				LightEmission = 0.05,
				Size = seq(0, cap(blastRadius * 0.55), 1, cap(blastRadius * 1.1)),
				Transparency = seq(0, 0.35, 0.7, 0.55, 1, 1),
				Lifetime = NumberRange.new(6, 9),
				Speed = NumberRange.new(blastRadius * 0.25, blastRadius * 0.55),
				SpreadAngle = Vector2.new(80, 80),
				Drag = 1.1,
				Acceleration = Vector3.new(0, -blastRadius * 0.03, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-12, 12),
			})
			head:Emit(22)
		end
	end)

	task.delay(rise + 10, function()
		riser:Destroy()
	end)
end

local function blast(info: any)
	local position: Vector3 = info.position
	local blastRadius: number = info.blastRadius
	local order = rarityOrder(info.rarity)
	local r = blastRadius

	local host = fxPart()
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(position)
	host.Parent = fxFolder
	local centre = Instance.new("Attachment")
	centre.Position = Vector3.new(0, 1, 0)
	centre.Parent = host

	-- THE FLASH: a sphere of light that is gone in a third of a second.
	local flash = fxPart("Ball")
	flash.Material = Enum.Material.Neon
	flash.Color = FLASH
	flash.Size = Vector3.one * r * 0.4
	flash.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	flash.Parent = fxFolder
	TweenService:Create(flash, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * r * 1.1,
	}):Play()
	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	task.delay(0.45, function()
		flash:Destroy()
	end)

	local light = Instance.new("PointLight")
	light.Color = FLASH
	light.Brightness = 10
	light.Range = math.min(60, r * 3)
	light.Shadows = false
	light.Parent = host
	TweenService:Create(light, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Color = FIRE_MID,
	}):Play()

	-- THE FIREBALL, rolling straight into smoke. Fire first, short and bright; the
	-- smoke is the same event a second later, dark and slow and much longer-lived.
	emitter(centre, {
		Texture = TEX_SMOKE,
		Color = colours(0, FLASH, 1, FIRE_HOT),
		LightEmission = 1,
		Size = seq(0, cap(r * 0.5), 1, cap(r * 0.9)),
		Transparency = seq(0, 0, 1, 1),
		Lifetime = NumberRange.new(0.18, 0.3),
		Speed = NumberRange.new(0, 1),
	}):Emit(3)

	emitter(centre, {
		Texture = TEX_FIRE,
		Color = colours(0, FIRE_HOT, 0.35, FIRE_MID, 1, FIRE_DEEP),
		LightEmission = 1,
		Size = seq(0, cap(r * 0.3), 0.4, cap(r * 0.55), 1, cap(r * 0.35)),
		Transparency = seq(0, 0, 0.7, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(r * 0.5, r * 1.1),
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

	-- THE PRESSURE RING: a flat disc of disturbed air skimming out along the ground,
	-- faster than anything else here. VelocityPerpendicular with a token upward speed
	-- lays the sprite flat.
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
	-- goes. One emitter per bearing, each pointing straight out (an emitter under an
	-- attachment fires along the attachment's own axes).
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
			Size = seq(0, cap(r * 0.22), 1, cap(r * 0.6)),
			Transparency = seq(0, 0.3, 0.6, 0.5, 1, 1),
			Lifetime = NumberRange.new(1.3, 2.2),
			Speed = NumberRange.new(r * 1.3, r * 1.9),
			SpreadAngle = Vector2.new(8, 8),
			Drag = 2.6,
			Acceleration = Vector3.new(0, 1.5, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
		}):Emit(3)
	end

	throwChunks(position, r, 8 + order * 2)

	if order >= COLUMN_FROM then
		raiseCloud(position, r, order >= CAP_FROM)
	end

	-- THE BOOM. Deeper for bigger ones, carried a long way.
	local boom = Instance.new("Sound")
	boom.SoundId = BOOM_SOUND
	boom.Volume = math.min(3, 1 + order * 0.2)
	boom.PlaybackSpeed = math.max(0.55, 1.1 - order * 0.07)
	boom.RollOffMode = Enum.RollOffMode.InverseTapered
	boom.RollOffMinDistance = r * 2
	boom.RollOffMaxDistance = 900
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

	task.delay(12, function()
		host:Destroy()
	end)

	-- How close were WE?
	local root = characterRoot()
	if root then
		local distance = (root.Position - position).Magnitude
		local near = math.clamp(1 - distance / (r * SHAKE_REACH), 0, 1)
		shake((0.6 + order * 0.25) * near ^ 1.5, 0.6 + order * 0.12)
		flashScreen(math.clamp(1 - distance / (r * FLASH_REACH), 0, 1) ^ 2)
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
	heart: BasePart,
	light: PointLight,
	motes: ParticleEmitter,
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

	-- The broken lip: slabs of ground kicked up and left leaning outward round the rim.
	-- Straight-edged rotated blocks, not a painted ring.
	local slabs = 10 + order
	for index = 1, slabs do
		local angle = (index / slabs) * math.pi * 2 + math.random() * 0.3
		local slab = fxPart()
		slab.Material = Enum.Material.Slate
		slab.Color = SCORCH:Lerp(ASH, math.random())
		local w = radius * (0.12 + math.random() * 0.1)
		slab.Size = Vector3.new(w, w * (0.25 + math.random() * 0.25), w * (0.6 + math.random() * 0.5))
		local at = position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * (0.62 + math.random() * 0.1)
		slab.CFrame = CFrame.lookAt(at, at + Vector3.new(math.cos(angle), 0, math.sin(angle)))
			* CFrame.Angles(math.rad(-15 - math.random() * 20), 0, math.rad((math.random() - 0.5) * 20))
			+ Vector3.new(0, slab.Size.Y * 0.3, 0)
		onGround(slab, 0)
	end

	-- Fissures: the ground split open and glowing, radiating from the centre.
	local fissures: { BasePart } = {}
	local count = 6 + order
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + (math.random() - 0.5) * 0.5
		local length = radius * (0.3 + math.random() * 0.4)
		local fissure = fxPart()
		fissure.Material = Enum.Material.Neon
		fissure.Color = RAD_GLOW
		fissure.Size = Vector3.new(0.18 + math.random() * 0.22, 0.08, length)
		local mid = position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius * 0.08 + length / 2)
		fissure.CFrame = CFrame.lookAt(mid, mid + Vector3.new(math.cos(angle), 0, math.sin(angle))) + Vector3.new(0, 0.12, 0)
		fissure.Parent = folder
		table.insert(fissures, fissure)
	end

	-- THE ORB. A ForceField-material shell reads as a shimmer of hot air rather than a
	-- solid; a faint haze just inside it gives it a body; a small hot heart on the
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

	local heart = fxPart("Ball")
	heart.Material = Enum.Material.Neon
	heart.Color = RAD_GLOW
	heart.Transparency = 0.25
	heart.Size = Vector3.one * math.max(1, radius * 0.16)
	heart.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0))
	heart.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = RAD_GLOW
	light.Brightness = 2.5
	light.Range = math.min(60, radius * 1.6)
	light.Shadows = false
	light.Parent = heart

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
		heart = heart,
		light = light,
		motes = motes,
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
		fx.heart.Transparency = 1 - 0.75 * strength * (0.85 + 0.15 * math.sin(clock * 6))
		fx.light.Brightness = 2.5 * strength
		fx.motes.Rate = fx.rate * strength
		for _, fissure in fx.fissures do
			fissure.Transparency = 1 - strength * (0.75 + 0.25 * math.sin(clock * 3 + fissure.Size.Z))
		end
		-- The scorch outlives the heat a little, then goes with the marker.
		for _, entry in fx.ground do
			entry.part.Transparency = entry.base + (1 - entry.base) * math.clamp(1 - strength * 1.5, 0, 1)
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
	local fx: FuseFx = { instance = instance, role = if role == "lump" then "lump" else "spot", nextTick = 0 }

	if fx.role == "lump" then
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
	else
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

function DetonationController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "DetonationFx"
	fxFolder.Parent = Workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "DetonationFlash"
	gui.IgnoreGuiInset = true
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

	-- Camera shake, after the camera has had its turn so it is an offset on this
	-- frame's view rather than a fight with the camera script over it.
	RunService:BindToRenderStep("DetonationShake", Enum.RenderPriority.Camera.Value + 2, function()
		if #shakes == 0 then
			return
		end
		local clock = os.clock()
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
		local camera = Workspace.CurrentCamera
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
