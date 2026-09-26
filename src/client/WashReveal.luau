--!strict
--[[
	WashReveal.luau — the last chunk comes off, and the bay puts on a show about it.

	THE STAR IS THE REAL MODEL. The nuke that was just washed is still turning on the
	stand, clean, with its own FX switched on the moment the crust went (ItemFxController),
	so there is no card, no picture of a nuke and no ViewportFrame here. The camera never
	leaves the player's head: it swings to put the nuke a little above the middle of the
	screen and ZOOMS in (field of view, not distance) until it fills about 40% of the
	height. A shot taken from the one place the wash already proved is clear cannot clip
	into the gantry or the tub the way a camera flown round the stand could.

	EVERYTHING ELSE FRAMES IT:
	  * the background drops out of focus (a DepthOfFieldEffect on Lighting),
	  * the turntable kicks round fast and settles, so you see the whole thing,
	  * a rarity-coloured light comes up on it, with a burst of real sparks from Epic up
	    and a flash of the rarity's colour from Legendary up,
	  * rays spin out from BEHIND it -- they start outside its silhouette, because a GUI
	    draws over the world and a ray across the nuke would be a ray on top of it,
	  * and the words land in the lower third: NEW FIND! / IDENTIFIED, the name, rarity
	    and weight, and the price counting up.

	WashController drives it. `play` is called when a staged ItemIdentified arrives,
	`drive` from its render step in place of the aim camera, `stop` from teardown -- which
	runs behind the exit wipe, so nothing here needs an exit animation of its own. The
	ScreenGui is built per show and destroyed after it rather than kept, because the bay's
	hideHud stows every LayerCollector it finds at session start, this one included.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Crates = require(Shared.Config.Crates)
local Tuning = require(Shared.Config.Tuning)

local UIKit = require(script.Parent.UIKit)

local WashReveal = {}

local T = {
	-- The shot. SWING is how long the look takes to settle on the nuke; FILL is how much
	-- of the screen's height its longest side ends up covering; SCREEN_Y is where its
	-- centre sits, from the top, leaving the lower third for the words. PUSH is the
	-- extra slow zoom across the rest of the hold.
	SWING = 0.55,
	FILL = 0.4,
	SCREEN_Y = 0.4,
	FOV_MIN = 12,
	PUSH = 0.08,

	-- The turntable runs SPIN_BOOST times its usual speed at the reveal and eases back
	-- to normal over SPIN_SETTLE seconds.
	SPIN_BOOST = 6,
	SPIN_SETTLE = 1.4,

	-- The rays, in fractions of screen height. Each pair is one thin arm through the
	-- nuke with the middle cut out, so RAY_PAIRS = 8 is sixteen rays.
	RAY_PAIRS = 8,
	RAY_WIDTH = 0.04,
	RAY_LENGTH = 0.6,
	RAY_GAP = 1.2,
	RAY_SPIN = 14,
	RAY_ALPHA = 0.3,

	-- The timeline, in seconds from the last chunk coming off.
	RAYS_AT = 0.2,
	RAYS_GROW = 0.45,
	RING_TIME = 0.7,
	RIBBON_AT = 0.4,
	NAME_AT = 0.5,
	PILL_AT = 0.75,
	VALUE_AT = 0.9,
	RECORD_AT = 0.6,
	COUNT_TIME = 0.9,

	-- Which rarities (by Rarity order) earn the extras.
	SPARKS_FROM = 5, -- Epic
	FLASH_FROM = 6, -- Legendary

	GOLD = Color3.fromHex("FFD23F"),
	RIBBON_NEW = Color3.fromHex("E0362E"),
	RIBBON_KNOWN = Color3.fromHex("3A434F"),
	INK = Color3.fromHex("0B0D10"),
}

type Beat = { at: number, run: () -> (), done: boolean }

type Show = {
	started: number,
	fromRotation: CFrame,
	fromFov: number,
	extent: number,
	value: number?,
	gui: ScreenGui,
	arms: { Frame },
	rays: { Frame },
	ring: Frame,
	ringStroke: UIStroke,
	valueLabel: TextLabel?,
	spot: Part,
	dof: DepthOfFieldEffect,
	beats: { Beat },
}

local show: Show? = nil

--- Where the hose goes while the show is on, relative to the aim eye: down and in, out
--- of the bottom of the shot. The barrel otherwise hangs in the lower third, right where
--- the words land. WashController eases it there with its usual nozzle catch-up, so it
--- reads as the player lowering the hose to look.
WashReveal.HOSE_DROP = CFrame.new(0.9, -2.8, -0.4)

-- ── Formatting ──────────────────────────────────────────────────────

--- "$142,000" -- the whole number, grouped. This is the one time the price is the
--- headline, so it is not abbreviated the way the cash badge's $142.0K is.
local function money(amount: number): string
	local grouped = tostring(math.floor(amount + 0.5))
	while true do
		local nextText, count = string.gsub(grouped, "^(%-?%d+)(%d%d%d)", "%1,%2")
		grouped = nextText
		if count == 0 then
			break
		end
	end
	return `${grouped}`
end

--- Same ladder as DetectorController's banner: two sig figs under a kilo.
local function formatWeight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

--- "PRISTINE LEGENDARY", "PREWAR SEALED EPIC", or just "RARE".
local function rarityLine(found: any): string
	local modifier = if type(found.modifier) == "string" and found.modifier ~= "None"
		then string.gsub(found.modifier, "(%l)(%u)", "%1 %2") .. " "
		else ""
	local line = string.upper(modifier .. tostring(found.rarity))
	if type(found.weight) == "number" then
		line ..= `  \u{00B7}  {string.upper(formatWeight(found.weight))}`
	end
	return line
end

-- ── Building ────────────────────────────────────────────────────────

local function scaler(parent: GuiObject): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = parent
	return scale
end

--- Show `object` and tween its UIScale from `from` to 1.
local function pop(object: GuiObject, scale: UIScale, from: number, time: number)
	scale.Scale = from
	object.Visible = true
	TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--- Show `object` sliding up into place from a little below where it sits.
local function rise(object: GuiObject, scale: UIScale)
	local home = object.Position
	object.Position = home + UDim2.fromOffset(0, 26)
	scale.Scale = 0.7
	object.Visible = true
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(object, info, { Position = home }):Play()
	TweenService:Create(scale, info, { Scale = 1 }):Play()
end

local function buildRays(root: Frame, colour: Color3): ({ Frame }, { Frame })
	local arms, rays = {}, {}
	for _ = 1, T.RAY_PAIRS do
		local arm = Instance.new("Frame")
		arm.Name = "RayArm"
		arm.AnchorPoint = Vector2.new(0.5, 0.5)
		arm.BackgroundTransparency = 1
		arm.Size = UDim2.fromOffset(0, 0)
		arm.Parent = root
		table.insert(arms, arm)

		-- side 0 is the ray above the nuke, side 1 the one below; each fades out toward
		-- its own outer end.
		for side = 0, 1 do
			local ray = Instance.new("Frame")
			ray.Name = "Ray"
			ray.AnchorPoint = Vector2.new(0, side)
			ray.Position = UDim2.fromScale(0, side)
			ray.Size = UDim2.fromScale(1, 0)
			ray.BackgroundColor3 = colour
			ray.BorderSizePixel = 0
			ray.Parent = arm

			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Transparency = if side == 0
				then NumberSequence.new(1, T.RAY_ALPHA)
				else NumberSequence.new(T.RAY_ALPHA, 1)
			gradient.Parent = ray
			table.insert(rays, ray)
		end
	end
	return arms, rays
end

--- A pill-shaped chip that sizes itself to its text.
local function chip(parent: Instance, text: string, fill: Color3, ink: Color3, y: number): (Frame, UIScale)
	local frame = Instance.new("Frame")
	frame.Name = "Chip"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, y)
	frame.Size = UDim2.fromOffset(0, 42)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = fill
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIKit.C.outline
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 22)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = frame

	local label = UIKit.label(frame, {
		name = "Text",
		size = UDim2.fromScale(0, 1),
		text = text,
		font = UIKit.Font.hero,
		textSize = 22,
		color = ink,
		outline = false,
		shadow = false,
	})
	label.AutomaticSize = Enum.AutomaticSize.X

	return frame, scaler(frame)
end

-- ── The show ────────────────────────────────────────────────────────

function WashReveal.active(): boolean
	return show ~= nil
end

--- How much faster than usual the turntable should turn right now.
function WashReveal.spinRate(): number
	local current = show
	if current == nil then
		return 1
	end
	local left = math.max(0, 1 - (os.clock() - current.started) / T.SPIN_SETTLE)
	return 1 + (T.SPIN_BOOST - 1) * left * left
end

function WashReveal.stop()
	local current = show
	if current == nil then
		return
	end
	show = nil
	current.gui:Destroy()
	current.spot:Destroy()
	current.dof:Destroy()
end

--- Start the show. `center`/`extent` are the nuke's bounding box on the stand, read
--- once for the lights and the framing (it turns in place, so neither moves much).
function WashReveal.play(found: any, camera: Camera, center: Vector3, extent: number)
	WashReveal.stop()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end

	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else UIKit.C.text
	local crate = if Crates.has(found.crate) then Crates.get(found.crate) else nil
	local order = if def then def.order else 1

	local gui = Instance.new("ScreenGui")
	gui.Name = "WashReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- ray positions are viewport pixels from WorldToViewportPoint
	-- ...measured from the true screen corner, so no notch inset either (UIKit's "The notch").
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Under the bay's own WashBay layer (200), whose exit wipe has to cover this.
	gui.DisplayOrder = 199

	local root = Instance.new("Frame")
	root.Name = "Show"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local arms, rays = buildRays(root, colour)

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = root
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = colour
	ringStroke.Thickness = 8
	ringStroke.Parent = ring

	-- The words, on the HUD's design canvas so they scale like everything else.
	local canvas = UIKit.canvas(root, 2)

	local ribbon = UIKit.panel(canvas, {
		name = "Ribbon",
		size = UDim2.fromOffset(300, 58),
		position = UDim2.fromScale(0.5, 0.12),
		anchorPoint = Vector2.new(0.5, 0.5),
		-- A dirty supply crate coming clean (WashService) wears its own colour and says so.
		color = if crate then Color3.fromHex(crate.color) elseif found.firstFind then T.RIBBON_NEW else T.RIBBON_KNOWN,
		transparency = 0,
		strokeColor = UIKit.C.outline,
		strokeThickness = 4,
		cornerRadius = UDim.new(0, 12),
		visible = false,
	})
	UIKit.label(ribbon, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		text = if crate then "SUPPLY CRATE!" elseif found.firstFind then "NEW FIND!" else "IDENTIFIED",
		font = UIKit.Font.hero,
		textSize = 32,
		xAlign = Enum.TextXAlignment.Center,
		color = Color3.new(1, 1, 1),
	})
	local ribbonScale = scaler(ribbon)

	local name = UIKit.label(canvas, {
		name = "ItemName", -- not "Name": that is a property on every Instance
		size = UDim2.fromOffset(1200, 96),
		position = UDim2.fromScale(0.5, 0.69),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = tostring(found.name),
		font = UIKit.Font.hero,
		textSize = 78,
		xAlign = Enum.TextXAlignment.Center,
		color = Color3.new(1, 1, 1),
		visible = false,
	})
	local nameScale = scaler(name)

	local pill, pillScale = chip(canvas, rarityLine(found), colour, T.INK, 0.785)
	-- The star rating hangs under the pill and pops in with it.
	UIKit.label(pill, {
		name = "Stars",
		size = UDim2.fromOffset(300, 24),
		position = UDim2.new(0.5, 0, 1, 4),
		anchorPoint = Vector2.new(0.5, 0),
		text = Rarity.starText(found.rarity),
		font = UIKit.Font.hero,
		textSize = 24,
		xAlign = Enum.TextXAlignment.Center,
		color = T.GOLD,
	})

	-- NEW HEAVIEST: this one out-weighs the index's record for it (IdentifyService's
	-- `previousBest`, never set on a first find). Gold, under the ribbon, with the
	-- record it just beat.
	local record: Frame? = nil
	local recordScale: UIScale? = nil
	if type(found.previousBest) == "number" and type(found.weight) == "number" then
		record, recordScale = chip(
			canvas,
			`NEW HEAVIEST!  {UIKit.formatKg(found.weight)}  (was {UIKit.formatKg(found.previousBest)})`,
			T.GOLD,
			T.INK,
			0.205
		)
	end

	local valueLabel: TextLabel? = nil
	local valueScale: UIScale? = nil
	if type(found.value) == "number" then
		local label = UIKit.label(canvas, {
			name = "Value",
			size = UDim2.fromOffset(600, 50),
			position = UDim2.fromScale(0.5, 0.87),
			anchorPoint = Vector2.new(0.5, 0.5),
			text = money(0),
			font = UIKit.Font.hero,
			textSize = 42,
			xAlign = Enum.TextXAlignment.Center,
			color = T.GOLD,
			visible = false,
		})
		valueLabel = label
		valueScale = scaler(label)
	end

	-- The 3D half, client-local under the camera: a rarity light on the nuke, and sparks.
	local spot = Instance.new("Part")
	spot.Name = "WashRevealSpot"
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.Transparency = 1
	spot.Size = Vector3.new(0.2, 0.2, 0.2)
	spot.CFrame = CFrame.new(center)
	spot.Parent = camera

	local light = Instance.new("PointLight")
	light.Color = colour
	-- Tight: a glow on the nuke, not a lamp for the room. At four times the nuke's size
	-- it lit the whole bay the rarity's colour and the scene went sepia.
	light.Range = math.clamp(extent * 1.6, 3, 6)
	light.Brightness = 5
	light.Shadows = false
	light.Parent = spot
	TweenService:Create(light, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Brightness = 1.5 }):Play()

	local sparks: ParticleEmitter? = nil
	if order >= T.SPARKS_FROM then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), colour)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, extent * 0.14),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(extent * 2.5, extent * 5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 4
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.Parent = spot
		sparks = emitter
	end

	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "WashRevealFocus"
	dof.NearIntensity = 0
	dof.FarIntensity = 0
	dof.FocusDistance = (center - camera.CFrame.Position).Magnitude
	dof.InFocusRadius = extent * 1.2
	dof.Parent = Lighting
	TweenService:Create(dof, TweenInfo.new(T.SWING), { FarIntensity = 0.75 }):Play()

	if order >= T.FLASH_FROM then
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = colour
		flash.BackgroundTransparency = 0.25
		flash.BorderSizePixel = 0
		flash.ZIndex = 3
		flash.Parent = root
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	end

	local beats: { Beat } = {
		{
			at = T.RAYS_AT,
			done = false,
			run = function()
				if sparks then
					sparks:Emit(14 + (order - T.SPARKS_FROM) * 10)
				end
			end,
		},
		{ at = T.RIBBON_AT, done = false, run = function()
			pop(ribbon, ribbonScale, 0, 0.35)
		end },
		{ at = T.NAME_AT, done = false, run = function()
			pop(name, nameScale, 2.6, 0.45)
		end },
		{ at = T.PILL_AT, done = false, run = function()
			rise(pill, pillScale)
		end },
		{ at = T.RECORD_AT, done = false, run = function()
			if record and recordScale then
				pop(record, recordScale, 0, 0.35)
			end
		end },
		{
			at = T.VALUE_AT,
			done = false,
			run = function()
				if valueLabel and valueScale then
					rise(valueLabel, valueScale)
				end
			end,
		},
	}

	gui.Parent = playerGui
	show = {
		started = os.clock(),
		fromRotation = camera.CFrame.Rotation,
		fromFov = camera.FieldOfView,
		extent = math.max(extent, 0.5),
		value = if type(found.value) == "number" then found.value else nil,
		gui = gui,
		arms = arms,
		rays = rays,
		ring = ring,
		ringStroke = ringStroke,
		valueLabel = valueLabel,
		spot = spot,
		dof = dof,
		beats = beats,
	}
end

--- One frame of the show: the camera, then everything pinned to where the nuke landed
--- on screen. Called from WashController's render step in place of the aim camera, with
--- the eye it would have used and the nuke's current centre.
function WashReveal.drive(camera: Camera, eye: Vector3, center: Vector3)
	local current = show
	if current == nil then
		return
	end
	local t = os.clock() - current.started

	-- THE ZOOM. The field of view at which the nuke's longest side covers FILL of the
	-- screen from where you are standing, tightened a little more across the hold.
	local distance = math.max((center - eye).Magnitude, 0.5)
	local fitted = 2 * math.deg(math.atan(current.extent / (2 * T.FILL * distance)))
	local hold = math.clamp((t - T.SWING) / math.max(Tuning.WASH_REVEAL_HOLD - T.SWING, 0.1), 0, 1)
	local goalFov = math.clamp(fitted * (1 - T.PUSH * hold), T.FOV_MIN, math.max(current.fromFov, T.FOV_MIN))

	local k = math.clamp(t / T.SWING, 0, 1)
	local ease = 1 - (1 - k) ^ 3
	local fov = current.fromFov + (goalFov - current.fromFov) * ease

	-- Aim a touch BELOW the nuke so it sits at SCREEN_Y rather than dead centre. Pitch
	-- only, off a level lookAt, so the horizon stays flat through the swing.
	local drop = math.atan((0.5 - T.SCREEN_Y) * 2 * math.tan(math.rad(fov) / 2))
	local goal = CFrame.lookAt(eye, center) * CFrame.Angles(-drop, 0, 0)
	camera.CFrame = CFrame.new(eye) * current.fromRotation:Lerp(goal.Rotation, ease)
	camera.FieldOfView = fov
	camera.Focus = CFrame.new(center)
	current.dof.FocusDistance = distance

	-- THE RAYS, pinned to wherever the nuke is on screen this frame (it moves through
	-- the swing), starting just outside its silhouette.
	local screen = camera:WorldToViewportPoint(center)
	local height = camera.ViewportSize.Y
	local depth = math.max(screen.Z, 0.1)
	local radius = (current.extent / 2) / (depth * math.tan(math.rad(fov) / 2)) * (height / 2)
	local inner = radius * T.RAY_GAP

	local grow = math.clamp((t - T.RAYS_AT) / T.RAYS_GROW, 0, 1)
	local length = 0
	if grow > 0 then
		-- ease-out-back: overshoots a little, then settles
		local c = 1.70158
		local g = grow - 1
		length = T.RAY_LENGTH * height * (1 + (c + 1) * g ^ 3 + c * g ^ 2)
	end
	local width = T.RAY_WIDTH * height
	local spin = T.RAY_SPIN * t
	for index, arm in current.arms do
		arm.Position = UDim2.fromOffset(screen.X, screen.Y)
		arm.Size = UDim2.fromOffset(width, 2 * (inner + math.max(length, 0)))
		arm.Rotation = spin + (index - 1) * (180 / T.RAY_PAIRS)
	end
	for _, ray in current.rays do
		ray.Size = UDim2.new(1, 0, 0, math.max(length, 0))
	end

	-- One shockwave ring out from the nuke as the rays arrive.
	local ringK = (t - T.RAYS_AT) / T.RING_TIME
	if ringK >= 0 and ringK <= 1 then
		local size = 2 * inner * (1 + 1.4 * ringK)
		current.ring.Visible = true
		current.ring.Position = UDim2.fromOffset(screen.X, screen.Y)
		current.ring.Size = UDim2.fromOffset(size, size)
		current.ringStroke.Transparency = ringK
	else
		current.ring.Visible = false
	end

	for _, beat in current.beats do
		if not beat.done and t >= beat.at then
			beat.done = true
			beat.run()
		end
	end

	local valueLabel = current.valueLabel
	if valueLabel and current.value then
		local countK = math.clamp((t - T.VALUE_AT) / T.COUNT_TIME, 0, 1)
		valueLabel.Text = money(current.value * (1 - (1 - countK) ^ 3))
	end
end

return WashReveal
