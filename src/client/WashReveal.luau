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
	  * a red award ribbon unfurls up top -- NEW FIND! / FIRST DISCOVERY, forked tails, glints
	    (none on a repeat) -- and the words land in the lower third: the name, rarity
	    and weight, and the price and what it pays per second on a stand counting up,
	  * and once they are down, its quality (Pristine, Cracked...) slams onto the nuke as a
	    rubber stamp with what it does to the price, and a big size roll (HUGE / GIGA)
	    slams a second one just under it.

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
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Payload = require(Shared.Config.Payload)
local Crates = require(Shared.Config.Crates)
local Tuning = require(Shared.Config.Tuning)

local UIKit = require(script.Parent.UIKit)
local StarLine = require(script.Parent.StarLine)
local Prefs = require(script.Parent.Prefs)

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
	TAILS_AT = 0.65,
	NAME_AT = 0.5,
	PILL_AT = 0.75,
	VALUE_AT = 0.9,
	RECORD_AT = 0.6,
	COUNT_TIME = 0.9,
	HINT_AT = 0.4,
	STAMP_AT = 1.25,
	SECOND_STAMP_AT = 1.55,

	-- Which rarities (by Rarity order) earn the extras.
	SPARKS_FROM = 5, -- Epic
	FLASH_FROM = 6, -- Legendary

	GOLD = Color3.fromHex("FFD23F"),
	-- The skip hint: a bright green that stands out against every background.
	HINT_GREEN = Color3.fromHex("5CFF5C"),
	RIBBON_NEW = Color3.fromHex("E0362E"),
	INK = Color3.fromHex("0B0D10"),

	-- The award ribbon, in design px: the middle band, and a forked tail tucked behind
	-- each end, hung a little lower than the band. NOTCH is how deep each fork cuts.
	RIBBON_SIZE = Vector2.new(460, 80),
	TAIL_SIZE = Vector2.new(110, 70),
	TAIL_OUT = 300, -- from the band's centre to a tail's outer end
	TAIL_DROP = 18,
	TAIL_TUCK = 80, -- how far behind the band the tails start before they flick out
	NOTCH = 29,
	RIBBON_STROKE = 5,
	-- The glints round the ribbon once it is up: offset from its centre, size, delay.
	GLINTS = {
		{ x = -255, y = -55, size = 30, at = 0.8 },
		{ x = 255, y = -47, size = 30, at = 0.95 },
		{ x = -190, y = 66, size = 20, at = 1.1 },
		{ x = 211, y = 64, size = 22, at = 1.2 },
	},
}

-- The stamps' colours: StandCardController's sticker colours, so a quality reads the
-- same on the stand as it did here, and DetectorController's callout colours for size.
local MODIFIER_COLOR: { [string]: Color3 } = {
	Pristine = Color3.fromHex("7DF9FF"),
	Irradiated = Color3.fromHex("A3FF3C"),
	Fused = Color3.fromHex("FF8A3D"),
	Cracked = Color3.fromHex("A7ADB4"),
}
local CALLOUT_COLOR: { [string]: Color3 } = {
	GIGA = Color3.fromHex("FACC15"),
	HUGE = Color3.fromHex("F59E0B"),
}

-- Where each stamp lands on the canvas: X in design px right of centre (the nuke is
-- centred, so this is "on its right-hand side" on any screen width), Y as a fraction
-- of the height (the nuke spans roughly 0.2..0.6, see SCREEN_Y/FILL), and its tilt.
-- The first is the only one most finds get; the second sits under it, tilted the other way.
local STAMP_SPOTS = {
	{ x = 90, y = 0.35, rotation = -12, textSize = 35 },
	{ x = 115, y = 0.5, rotation = 7, textSize = 29 },
}
-- An announced drop (Config/RareDrop) can carry 3 or 4 buffs: a tighter pile that
-- starts higher, so the last one still clears the name at 0.69.
local STAMP_SPOTS_STACKED = {
	{ x = 90, y = 0.25, rotation = -12, textSize = 33 },
	{ x = 115, y = 0.35, rotation = 7, textSize = 30 },
	{ x = 95, y = 0.45, rotation = -8, textSize = 28 },
	{ x = 120, y = 0.55, rotation = 6, textSize = 27 },
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
	rate: number?,
	rateLabel: TextLabel?,
	rainbowName: TextLabel?,
	rainbowPill: Frame?,
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

--- "$2.00/s", "$236/s", "$6.1K/s", "$1.2M/s" -- StandCardController's ladder, so the
--- rate printed here is the one the stand card shows once it is placed.
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 100_000 then
		return string.format("$%.0fK/s", perSecond / 1000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

--- Same ladder as DetectorController's banner: two sig figs under a kilo.
local function formatWeight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

--- "x2", "x0.4", "x1.8": a value multiplier, to one decimal place at most.
local function multiplier(mult: number): string
	local rounded = math.floor(mult * 10 + 0.5) / 10
	return if rounded == math.floor(rounded) then `x{math.floor(rounded)}` else `x{rounded}`
end

type StampSpec = { text: string, colour: Color3, mult: number }

--- What gets stamped on this find, in slam order: its qualities (an announced drop
--- can stack several, Rarity.qualities), then its size roll. Any can be missing; a
--- plain find gets no stamps at all.
local function stampsFor(found: any): { StampSpec }
	local stamps: { StampSpec } = {}
	local modifier = if type(found.modifier) == "string" then found.modifier else nil
	for _, quality in Rarity.qualities(modifier, found.bonus) do
		local def = Rarity.MODIFIERS[quality]
		table.insert(stamps, {
			text = string.upper((string.gsub(quality, "(%l)(%u)", "%1 %2"))),
			colour = MODIFIER_COLOR[quality] or UIKit.C.text,
			mult = if def then def.valueMult else 1,
		})
	end
	if type(found.uid) == "string" then
		local size = Payload.forUid(found.uid)
		local callout = Payload.calloutFor(size)
		if callout then
			table.insert(stamps, { text = callout, colour = CALLOUT_COLOR[callout] or T.GOLD, mult = size })
		end
	end
	return stamps
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

--- A plain filled box, the brick the ribbon's tails are laid from.
local function block(parent: Instance, position: Vector2, size: Vector2, colour: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = colour
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

--- A box with one triangle cut off it along a corner-to-corner diagonal. A UIGradient
--- works in the box's own 0..1 space, so at +-45 degrees its halfway line IS a diagonal
--- whatever the box's shape, and a hard step there in its transparency is a clean
--- straight cut -- the only way to get a slanted edge out of a Frame.
local function cutBlock(parent: Instance, position: Vector2, size: Vector2, colour: Color3, rotation: number, cutLow: boolean)
	local frame = block(parent, position, size, colour)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	local low, high = if cutLow then 1 else 0, if cutLow then 0 else 1
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, low),
		NumberSequenceKeypoint.new(0.495, low),
		NumberSequenceKeypoint.new(0.505, high),
		NumberSequenceKeypoint.new(1, high),
	})
	gradient.Parent = frame
end

--- One forked ribbon tail filling `size` at `origin`, notched `notch` deep into its
--- outer end (the left end when `left`). Laid as a box plus two cut corner blocks, one
--- each side of the fork's point -- 1 px of overlap so no seam shows between them.
local function forkedTail(parent: Instance, origin: Vector2, size: Vector2, notch: number, colour: Color3, left: boolean)
	local half = size.Y / 2
	if left then
		block(parent, origin + Vector2.new(notch - 1, 0), Vector2.new(size.X - notch + 1, size.Y), colour)
		cutBlock(parent, origin, Vector2.new(notch, half + 1), colour, -45, true)
		cutBlock(parent, origin + Vector2.new(0, half), Vector2.new(notch, half), colour, 45, true)
	else
		local x = size.X - notch
		block(parent, origin, Vector2.new(x + 1, size.Y), colour)
		cutBlock(parent, origin + Vector2.new(x, 0), Vector2.new(notch, half + 1), colour, 45, false)
		cutBlock(parent, origin + Vector2.new(x, half), Vector2.new(notch, half), colour, -45, false)
	end
end

--- A tail with the HUD's black outline: the same fork a stroke wider all round in
--- black, under the coloured one. Its frame is the tail's own box, for sliding.
local function outlinedTail(parent: Instance, colour: Color3, left: boolean): Frame
	local s = T.RIBBON_STROKE
	local frame = Instance.new("Frame")
	frame.Name = if left then "TailL" else "TailR"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(T.TAIL_SIZE.X, T.TAIL_SIZE.Y)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	forkedTail(frame, Vector2.new(-s, -s), T.TAIL_SIZE + Vector2.new(2 * s, 2 * s), T.NOTCH, UIKit.C.outline, left)
	-- The tail is a shade of the band: the back of the ribbon, folded behind it.
	forkedTail(frame, Vector2.zero, T.TAIL_SIZE, T.NOTCH, colour:Lerp(Color3.new(0, 0, 0), 0.4), left)
	return frame
end

--- A white glint: two crossed bars, rounded. Hidden until it twinkles.
local function glint(parent: Instance, position: UDim2, size: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Glint"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 3 -- over the band and its tails
	frame.Visible = false
	frame.Parent = parent
	for _, rotation in { 0, 90 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(1, 0.22)
		bar.Rotation = rotation
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bar
	end
	scaler(frame)
	return frame
end

--- Pop a glint in, turning, and let it shrink away.
local function twinkle(frame: Frame)
	local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0
	frame.Rotation = 0
	frame.Visible = true
	TweenService:Create(frame, TweenInfo.new(0.7, Enum.EasingStyle.Linear), { Rotation = 90 }):Play()
	local grow = TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.2 })
	grow.Completed:Connect(function()
		local fade = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(scale, fade, { Scale = 0.4 }):Play()
		for _, bar in frame:GetChildren() do
			if bar:IsA("Frame") then
				TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	grow:Play()
end

--- A rubber stamp: the word and its "x2 VALUE" in `spec`'s colour, inside a border of the
--- same colour on a dark see-through plate, tilted. Hidden until it slams.
local function stamp(parent: Instance, spec: StampSpec, spot: typeof(STAMP_SPOTS[1])): (Frame, UIScale)
	local frame = Instance.new("Frame")
	frame.Name = "Stamp"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0.5, spot.x, spot.y, 0)
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Rotation = spot.rotation
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = spec.colour
	stroke.Thickness = 5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = frame
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 0)
	list.Parent = frame

	local word = UIKit.label(frame, {
		name = "Word",
		size = UDim2.fromOffset(0, spot.textSize + 4),
		text = spec.text,
		font = UIKit.Font.hero,
		textSize = spot.textSize,
		xAlign = Enum.TextXAlignment.Center,
		color = spec.colour,
		shadow = false, -- its drop shadow is a sibling label, which the list would stack
	})
	word.AutomaticSize = Enum.AutomaticSize.X
	word.LayoutOrder = 1

	local effect = UIKit.label(frame, {
		name = "Effect",
		size = UDim2.fromOffset(0, math.floor(spot.textSize * 0.55)),
		text = `{multiplier(spec.mult)} VALUE`,
		font = UIKit.Font.hero,
		textSize = math.floor(spot.textSize * 0.5),
		xAlign = Enum.TextXAlignment.Center,
		color = spec.colour,
		shadow = false, -- its drop shadow is a sibling label, which the list would stack
	})
	effect.AutomaticSize = Enum.AutomaticSize.X
	effect.LayoutOrder = 2

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

	-- THE AWARD RIBBON: a band that unfurls from its middle, a forked tail flicking out
	-- from behind each end, and glints round it. Always red for a new find, whatever the
	-- rarity; a dirty supply crate coming clean (WashService) wears its own colour and
	-- says so. A repeat find has nothing to announce and gets none of it.
	local announce = crate ~= nil or found.firstFind == true
	local ribbonColour = if crate then Color3.fromHex(crate.color) else T.RIBBON_NEW
	local ribbonAt = UDim2.fromScale(0.5, 0.12)
	local tails = {
		outlinedTail(canvas, ribbonColour, true),
		outlinedTail(canvas, ribbonColour, false),
	}
	local tailHome = {
		ribbonAt + UDim2.fromOffset(-T.TAIL_OUT + T.TAIL_SIZE.X / 2, T.TAIL_DROP),
		ribbonAt + UDim2.fromOffset(T.TAIL_OUT - T.TAIL_SIZE.X / 2, T.TAIL_DROP),
	}

	-- Built at full size and kept at zero width until it unfurls; it clips its words, so
	-- they are uncovered from the middle out as it opens.
	local ribbon = UIKit.panel(canvas, {
		name = "Ribbon",
		size = UDim2.fromOffset(0, T.RIBBON_SIZE.Y),
		position = ribbonAt,
		anchorPoint = Vector2.new(0.5, 0.5),
		color = ribbonColour,
		transparency = 0,
		strokeColor = UIKit.C.outline,
		strokeThickness = T.RIBBON_STROKE,
		cornerRadius = UDim.new(0, 4),
		zIndex = 2, -- over its tails
		visible = false,
	})
	ribbon.ClipsDescendants = true
	UIKit.label(ribbon, {
		name = "Text",
		size = UDim2.fromOffset(T.RIBBON_SIZE.X, 50),
		position = UDim2.fromScale(0.5, if crate then 0.5 else 0.4),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = if crate then "SUPPLY CRATE!" else "NEW FIND!",
		font = UIKit.Font.hero,
		textSize = 44,
		xAlign = Enum.TextXAlignment.Center,
		color = Color3.new(1, 1, 1),
	})
	if not crate then
		UIKit.label(ribbon, {
			name = "Subtitle",
			size = UDim2.fromOffset(T.RIBBON_SIZE.X, 18),
			position = UDim2.fromScale(0.5, 0.8),
			anchorPoint = Vector2.new(0.5, 0.5),
			text = "FIRST DISCOVERY",
			font = UIKit.Font.hero,
			textSize = 15,
			xAlign = Enum.TextXAlignment.Center,
			color = UIKit.C.outline,
			outline = false,
			shadow = false,
		})
	end

	local glints: { { frame: Frame, at: number } } = {}
	for _, spec in T.GLINTS do
		table.insert(glints, {
			frame = glint(canvas, ribbonAt + UDim2.fromOffset(spec.x, spec.y), spec.size),
			at = spec.at,
		})
	end

	local name = UIKit.label(canvas, {
		name = "ItemName", -- not "Name": that is a property on every Instance
		size = UDim2.fromOffset(1200, 96),
		position = UDim2.fromScale(0.5, 0.69),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = tostring(found.name),
		font = UIKit.Font.hero,
		textSize = 78,
		xAlign = Enum.TextXAlignment.Center,
		-- In its rarity's colour; an Anomaly's cycles the spectrum (drive).
		color = colour,
		visible = false,
	})
	local nameScale = scaler(name)

	-- Weight above the pill, the pill holds the rarity alone, the stars sit under it.
	-- All three are canvas children centred on x = 0.5: the stars used to hang inside the
	-- auto-sized pill, where their fixed width stretched and shifted it.
	local weight: TextLabel? = nil
	local weightScale: UIScale? = nil
	if type(found.weight) == "number" then
		local label = UIKit.label(canvas, {
			name = "Weight",
			-- Sized to fill the gap from the name down to the rarity pill.
			size = UDim2.fromOffset(600, 62),
			position = UDim2.fromScale(0.5, 0.772),
			anchorPoint = Vector2.new(0.5, 0.5),
			text = string.upper(formatWeight(found.weight)),
			font = UIKit.Font.hero,
			textSize = 56,
			xAlign = Enum.TextXAlignment.Center,
			color = Color3.new(1, 1, 1),
			visible = false,
		})
		weight = label
		weightScale = scaler(label)
	end

	local pill, pillScale = chip(canvas, string.upper(tostring(found.rarity)), colour, T.INK, 0.83)
	local stars = UIKit.label(canvas, {
		name = "Stars",
		size = UDim2.fromOffset(600, 28),
		position = UDim2.fromScale(0.5, 0.87),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		font = UIKit.Font.hero,
		textSize = 26,
		xAlign = Enum.TextXAlignment.Center,
		color = T.GOLD,
		visible = false,
	})
	StarLine.set(
		stars,
		Rarity.stars(
			found.rarity,
			found.modifier,
			if type(found.uid) == "string" then Payload.forUid(found.uid) else nil,
			found.bonus,
			Items.stageOf(found.itemId)
		)
	)
	local starsScale = scaler(stars)

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

	-- THE STAMPS, built now and slammed down by the beats below once the words are in.
	local stamps: { { frame: Frame, scale: UIScale } } = {}
	local specs = stampsFor(found)
	local spots = if #specs > #STAMP_SPOTS then STAMP_SPOTS_STACKED else STAMP_SPOTS
	for index, spec in specs do
		local spot = spots[index]
		if spot then
			local frame, scale = stamp(canvas, spec, spot)
			table.insert(stamps, { frame = frame, scale = scale })
		end
	end

	local valueLabel: TextLabel? = nil
	local valueScale: UIScale? = nil
	if type(found.value) == "number" then
		local label = UIKit.label(canvas, {
			name = "Value",
			size = UDim2.fromOffset(600, 50),
			-- Nudged up from 0.94 to make room for the rate under it.
			position = UDim2.fromScale(0.5, 0.925),
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

	-- What it pays per second on a stand (WashService's `rate`), in the cash badge's
	-- income green under the price, counting up with it.
	local rateLabel: TextLabel? = nil
	local rateScale: UIScale? = nil
	if type(found.rate) == "number" then
		local label = UIKit.label(canvas, {
			name = "Rate",
			size = UDim2.fromOffset(600, 38),
			position = UDim2.fromScale(0.5, 0.972),
			anchorPoint = Vector2.new(0.5, 0.5),
			text = "+" .. formatRate(0),
			font = UIKit.Font.hero,
			textSize = 32,
			xAlign = Enum.TextXAlignment.Center,
			color = UIKit.C.green,
			visible = false,
		})
		rateLabel = label
		rateScale = scaler(label)
	end

	-- The skip hint, top centre, above the ribbon where it is easy to spot. E/Q/B ends the
	-- show early (WashController's escape hatch); without this nobody knows they can.
	local gamepad = string.find(UserInputService:GetLastInputType().Name, "Gamepad") ~= nil
	local hint = UIKit.label(canvas, {
		name = "SkipHint",
		size = UDim2.fromOffset(500, 30),
		position = UDim2.fromScale(0.5, 0.04),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = if gamepad then "PRESS B TO SKIP" else "PRESS E TO SKIP",
		font = UIKit.Font.hero,
		textSize = 26,
		xAlign = Enum.TextXAlignment.Center,
		color = T.HINT_GREEN,
		visible = false,
	})
	local hintScale = scaler(hint)

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

	if order >= T.FLASH_FROM and not Prefs.get("reduceFlashing") then
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
			if not announce then
				return
			end
			ribbon.Visible = true
			TweenService:Create(
				ribbon,
				TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(T.RIBBON_SIZE.X, T.RIBBON_SIZE.Y) }
			):Play()
		end },
		{ at = T.TAILS_AT, done = false, run = function()
			if not announce then
				return
			end
			-- Out from behind the band, where they start tucked away out of sight.
			for index, tail in tails do
				local inward = if index == 1 then T.TAIL_TUCK else -T.TAIL_TUCK
				tail.Position = tailHome[index] + UDim2.fromOffset(inward, 0)
				tail.Visible = true
				TweenService:Create(
					tail,
					TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Position = tailHome[index] }
				):Play()
			end
		end },
		{ at = T.NAME_AT, done = false, run = function()
			pop(name, nameScale, 2.6, 0.45)
		end },
		{ at = T.PILL_AT, done = false, run = function()
			if weight and weightScale then
				rise(weight, weightScale)
			end
			rise(pill, pillScale)
			rise(stars, starsScale)
		end },
		{ at = T.RECORD_AT, done = false, run = function()
			if record and recordScale then
				pop(record, recordScale, 0, 0.35)
			end
		end },
		{ at = T.HINT_AT, done = false, run = function()
			rise(hint, hintScale)
		end },
		{
			at = T.VALUE_AT,
			done = false,
			run = function()
				if valueLabel and valueScale then
					rise(valueLabel, valueScale)
				end
				if rateLabel and rateScale then
					rise(rateLabel, rateScale)
				end
			end,
		},
	}
	if announce then
		for _, placed in glints do
			table.insert(beats, { at = placed.at, done = false, run = function()
				twinkle(placed.frame)
			end })
		end
	end
	for index, placed in stamps do
		table.insert(beats, {
			-- One every (SECOND - FIRST) seconds: a stacked drop's 3rd and 4th keep the beat.
			at = T.STAMP_AT + (index - 1) * (T.SECOND_STAMP_AT - T.STAMP_AT),
			done = false,
			-- Comes down from big, like it was brought down on the nuke from the camera.
			run = function()
				placed.scale.Scale = 2.6
				placed.frame.Visible = true
				TweenService:Create(
					placed.scale,
					TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end,
		})
	end

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
		rate = if type(found.rate) == "number" then found.rate else nil,
		rateLabel = rateLabel,
		rainbowName = if found.rarity == "Anomaly" then name else nil,
		rainbowPill = if found.rarity == "Anomaly" then pill else nil,
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

	local rainbowName, rainbowPill = current.rainbowName, current.rainbowPill
	if rainbowName and rainbowPill then
		local hue = Rarity.anomalyHue(os.clock() / Rarity.ANOMALY_CYCLE)
		rainbowName.TextColor3 = hue
		rainbowPill.BackgroundColor3 = hue
	end

	local valueLabel = current.valueLabel
	if valueLabel and current.value then
		local countK = math.clamp((t - T.VALUE_AT) / T.COUNT_TIME, 0, 1)
		valueLabel.Text = money(current.value * (1 - (1 - countK) ^ 3))
	end

	local rateLabel = current.rateLabel
	if rateLabel and current.rate then
		local countK = math.clamp((t - T.VALUE_AT) / T.COUNT_TIME, 0, 1)
		rateLabel.Text = "+" .. formatRate(current.rate * (1 - (1 - countK) ^ 3))
	end
end

return WashReveal
