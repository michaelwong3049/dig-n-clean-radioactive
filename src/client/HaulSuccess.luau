--!strict
--[[
	HaulSuccess.luau — the little "Success!" the haul panel leaves behind when a nuke
	comes all the way out.

	Round-5 mockup #2 with yellow rays, on request (2026-10-09). DetectorController plays
	it off the Unearthed remote: first the pull bar snaps to 100% and its outline flashes
	gold for a beat (HaulRope.step's `glow`), then the bar is gone and, in its exact spot,
	"Success!" scales up in a yellow-to-orange gradient with soft yellow rays turning
	slowly behind it, holds, and fades.

	Normal capitalisation ("Success!", not "SUCCESS!"), on request.

	Frames only, like the rest of the HUD. This module builds the pieces and draws them at
	a given time; DetectorController owns when, and keeps the root placed and scaled
	exactly like the haul panel.
]]

local UIKit = require(script.Parent.UIKit)

local HaulSuccess = {}

-- ── Timing, in seconds after the bar has gone ──────────────────────────────────────
HaulSuccess.DURATION = 1.55
local POP_UP = 0.15 -- scale 0.6 -> 1.15
local POP_SETTLE = 0.1 -- 1.15 -> 1
local FADE = 0.35 -- the last this-many seconds fade out
local RAYS_GROW = 0.2

-- ── Look ───────────────────────────────────────────────────────────────────────────
local TEXT = "Success!"
local TEXT_SIZE = 32
local TEXT_BOX = Vector2.new(320, 44)
local RAY_COUNT = 12 -- bars through the centre, so twice as many rays
local RAY_LENGTH = 190
local RAY_WIDTH = 9
local RAY_SPIN = 40 -- degrees per second
local RAY_OPACITY = 0.8
local RAY_COLOR = Color3.fromHex("FFE45A")
local GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFF6B0")),
	ColorSequenceKeypoint.new(0.45, Color3.fromHex("FFD23A")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("FF9F1A")),
})
-- Each ray fades out at both tips and thins toward the hub, where the word sits.
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.22, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(0.78, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})

export type Success = {
	root: Frame,
	text: TextLabel,
	textScale: UIScale,
	textStroke: UIStroke,
	rays: Frame,
	raysScale: UIScale,
	rayBars: { Frame },
}

--- Build into `parent` as a transparent frame of `size`, the word and rays centred on
--- `centre` (in that frame's own pixels). Hidden until draw().
function HaulSuccess.build(parent: Instance, size: UDim2, centre: Vector2): Success
	local root = Instance.new("Frame")
	root.Name = "HaulSuccess"
	root.Size = size
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent

	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromOffset(centre.X, centre.Y)
	rays.Size = UDim2.fromOffset(RAY_LENGTH, RAY_LENGTH)
	rays.BackgroundTransparency = 1
	rays.ZIndex = 40
	rays.Parent = root
	local raysScale = Instance.new("UIScale")
	raysScale.Parent = rays
	local rayBars = {}
	for i = 0, RAY_COUNT - 1 do
		local bar = Instance.new("Frame")
		bar.Name = "Ray"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(RAY_WIDTH, RAY_LENGTH)
		bar.Rotation = i * 180 / RAY_COUNT
		bar.BackgroundColor3 = RAY_COLOR
		bar.BorderSizePixel = 0
		bar.ZIndex = 40
		bar.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = RAY_FADE
		fade.Parent = bar
		table.insert(rayBars, bar)
	end

	local text = Instance.new("TextLabel")
	text.Name = "Word"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromOffset(centre.X, centre.Y)
	text.Size = UDim2.fromOffset(TEXT_BOX.X, TEXT_BOX.Y)
	text.BackgroundTransparency = 1
	text.Font = UIKit.Font.hero
	text.TextSize = TEXT_SIZE
	text.TextColor3 = Color3.new(1, 1, 1) -- the gradient colours it
	text.Text = TEXT
	text.ZIndex = 41
	text.Parent = root
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = GRADIENT
	gradient.Parent = text
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.new(0, 0, 0)
	textStroke.Thickness = UIKit.strokeThicknessFor(TEXT_SIZE)
	textStroke.Parent = text
	local textScale = Instance.new("UIScale")
	textScale.Parent = text

	return {
		root = root,
		text = text,
		textScale = textScale,
		textStroke = textStroke,
		rays = rays,
		raysScale = raysScale,
		rayBars = rayBars,
	}
end

--- Draw the moment `t` seconds in (0 .. DURATION); nil hides it.
function HaulSuccess.draw(s: Success, t: number?)
	if t == nil or t < 0 or t >= HaulSuccess.DURATION then
		s.root.Visible = false
		return
	end
	s.root.Visible = true

	local pop = if t < POP_UP then 0.6 + 0.55 * (t / POP_UP)
		elseif t < POP_UP + POP_SETTLE then 1.15 - 0.15 * ((t - POP_UP) / POP_SETTLE)
		else 1
	local left = HaulSuccess.DURATION - t
	local alpha = if left < FADE then left / FADE else 1

	s.textScale.Scale = pop
	s.text.TextTransparency = 1 - alpha
	s.textStroke.Transparency = 1 - alpha

	s.rays.Rotation = t * RAY_SPIN
	s.raysScale.Scale = 0.6 + 0.4 * math.min(1, t / RAYS_GROW)
	local rayAlpha = alpha * RAY_OPACITY
	for _, bar in s.rayBars do
		bar.BackgroundTransparency = 1 - rayAlpha
	end
end

return HaulSuccess
