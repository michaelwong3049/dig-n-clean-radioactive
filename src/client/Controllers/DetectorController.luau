--[[
	DetectorController.lua — the sweep, rendered.

	WHAT THIS DRAWS NOW, AND WHAT IT USED TO DRAW.
	It used to be a NEEDLE. The server sent one angle and one strength and the whole
	screen was derived from those two numbers, because the field was a secret and a
	direction was the most the client was allowed to know.

	The detector no longer works that way. Its radius REVEALS: every registerable
	signal inside it stands up out of the ground as an aura, and the server sends this
	client the ones it personally registers, as offsets from the player. So the dial
	is a RADAR SCOPE — you at the centre, your radius as the ring, a blip per contact.
	The direction problem the needle existed to solve does not exist any more; the
	world answers it directly.

	THE SCOPE IS NOT REDUNDANT WITH THE AURAS, and the reason is worth keeping.
	An aura is one shared part that every player in the server can see, but each
	player's ROLL for a signal is their own (DigService.rollFor) — signal X can be Rare
	for you and Common for the next player — so what "it is" cannot live on the shared
	part. The BLIP (and the haul panel) is where the per-player reading gets to live,
	because both are drawn from a payload only this client receives: the rarity, and now
	the "1 in N" odds too. None of it is clarity-gated any more (DigService.hintFor).
	Delete the scope and that readout loses its home. It WAS deleted for one pass and
	should not have been; back.

	IT IS IN THE BOTTOM-RIGHT CORNER NOW, ALONE, NOT IN THE INSTRUMENT BAND. It used to
	sit beside the dig button in the middle of the dock, which put a 180px dial in the
	busiest part of the screen and made INSTRUMENT_HEIGHT (and so RESERVE, and so
	every centred panel's headroom) 36px taller than the meter needed. Corner-anchored
	it costs the layout nothing: it shares only the INSTRUMENT_BOTTOM baseline with the
	meter diagonally opposite it — see Dock.SCOPE_BOTTOM. The index button briefly
	stacked above it here too, but has since moved to the opposite corner, above the
	cash badge; nothing shares this corner with the scope any more.

	NO SOUND. The detector used to carry hot/cold by audio — a rate-and-pitch ping
	keyed to the nearest contact, plus a chirp on each new reveal (PLAN §10.7's
	"sweep with your eyes half shut"). Both were removed on request. The feedback is
	entirely visual now: the scope dial and its blips on screen, and out in the world
	the aura wells and the range ring (FieldController).

	SCOPE_RADIUS stays local because nothing outside this file reads it, but it is
	DERIVED from Dock.SCOPE_DIAL rather than a second hardcode, because it drives the
	ring sizes, the sweep arm's length AND the blip polar-placement maths all at once
	— change the dial without updating this and blips cluster inside a ring that no
	longer matches what is drawn.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Detector = {}

-- Same fields UIKit.C already carries (panel/stroke/text/dim/green/amber/red/scope),
-- so every COLOR.xxx read throughout render/state logic below keeps working
-- unchanged — this is an alias, not a copy, on purpose.
local COLOR = UIKit.C

local DIAL_SIZE = Dock.SCOPE_DIAL
local SCOPE_RADIUS = Dock.SCOPE_DIAL / 2 - 15 -- px from the centre of the dial to the radius ring
local MAX_BLIPS = 12 -- matches DigService.MAX_CONTACTS; more would never arrive

-- The button's per-click kick. This is the ONLY instant feedback the mash has, and it
-- earns its place: SweepState arrives at 10 Hz, so the progress bar can be up to 100ms
-- behind a click, which on a verb this fast reads as unresponsiveness. The kick fires
-- off the local input instead, so the button answers the finger immediately while the
-- bar catches up. It deliberately reports the INPUT, never the outcome -- it is not
-- lying about progress the server may yet reject, it is confirming a click happened.
-- How long E must be held to commit to a signal. Long enough to read as a deliberate
-- act and to stop a stray E while running past a glow from rooting you mid-sprint;
-- short enough that it never feels like waiting. Lives here rather than in Config
-- because nothing about the game's balance reads it -- it is input feel, like the kick
-- below.
local LOCK_HOLD_SECONDS = 0.4

-- The pick-up prompt's face. ProximityPrompt.Style is Custom (see build), so Roblox
-- draws nothing itself and these drive our own billboard: how far it floats over the
-- buried signal, and the two tweens it opens and closes with. A "Back" ease on the way
-- in gives the card a small overshoot so it reads as landing on the spot.
local LOCKGUI_RISE = 2.4 -- studs above the signal the card hovers at rest
local LOCKGUI_SHOW_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LOCKGUI_HIDE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local YANK_KICK_SECONDS = 0.12
local YANK_KICK_SCALE = 0.05 -- how far the button swells at the peak of a kick

-- ── The haul widget's interior ──────────────────────────────────────────────────
-- ALL DERIVED FROM Dock.HAULPANEL_SIZE, never re-hardcoded against it.
--
-- THERE IS NO PANEL BEHIND ANY OF THIS ANY MORE. It used to be a 420x230 slab of
-- translucent black with a stroke round it, and the slab was the bulk — the content
-- inside it was never the problem. Removing it costs nothing that the pieces cannot
-- carry themselves: the bar is already a bordered vessel, the mash button already has
-- its own fill, and the two text lines get a text stroke instead (over open ground
-- there is no dark backing to read against any more, which is the one real bill this
-- comes with). The widget is a transparent container that only exists to be shown and
-- hidden as a unit.
--
-- ONE COLUMN, ORDERED THE WAY THE HAUL RUNS. PULL sits on top of the bar, the bar
-- climbs towards it, the magnet doing the pulling sits under the bar's foot, and the
-- way out sits under the magnet. The rarity/odds readout is beside the bar rather
-- than above it, so naming what you hooked costs no height at all.
local HAULTRACK_WIDTH = 72

-- The magnet glyph parks below the track. buildMagnetIcon draws into a fixed 30x26 box
-- of hand-placed rectangles, so it is enlarged with a UIScale rather than by retuning
-- five sets of coordinates -- MAGNET_HEIGHT is therefore the height the stack has to
-- RESERVE (the scaled one), not the height the glyph is drawn at.
local MAGNET_DRAWN = 26
local MAGNET_SCALE = 1.5
local MAGNET_HEIGHT = MAGNET_DRAWN * MAGNET_SCALE

-- THE BAR'S COLUMN IS AS WIDE AS THE WIDEST THING STACKED IN IT, which is the release
-- hint at the bottom rather than the bar itself — everything in the stack is centred
-- on the same axis, so the bar, the magnet and both bits of text line up down the
-- middle of it. The readout column takes whatever is left, and it needs enough of it
-- for "LEGENDARY" at hero/title weight -- the longest rarity in Rarity.ORDER, and the
-- one thing here that would clip rather than merely look cramped.
local HAULBAR_COL = 120
local HAULBAR_MID = HAULBAR_COL / 2
local HAULCOL_GAP = 14 -- bar column -> readout column
local HAULCOL_X = HAULBAR_COL + HAULCOL_GAP
local HAULCOL_WIDTH = Dock.HAULPANEL_SIZE.X.Offset - HAULCOL_X

-- The stack's own rows, top-down, and the bar's travel as whatever is left over. Named
-- rather than inlined because HAULTRACK_HEIGHT is derived from all of them at once: a
-- change to any row moves the bar's length rather than silently pushing the release
-- hint off the bottom.
local HAULBUTTON_HEIGHT = 46
local HAULBUTTON_GAP = 10 -- PULL -> the top of the bar

-- PULL'S OWN TEXT SIZE, and the one place here that does not use UIKit.TextSize. The
-- kit's scale tops out at title(26) below the hero(40) reserved for headlines, and at
-- 26 the word measured 61px inside a 120x46 plate -- a short label swimming in a big
-- button, which is what made it look wrong rather than merely small. 30 fills it
-- (68x30) without crowding the corners.
--
-- A LITERAL RATHER THAN A NEW SCALE ENTRY on purpose: UIKit's font header says the
-- sizes are underset for Gotham and asks for a retune "after looking at it in Studio"
-- -- but a retune moves every surface in the game, and this is one button. When that
-- retune happens this constant is a candidate to fold back in.
local HAULBUTTON_TEXT = 30
local MAGNET_GAP = 8 -- the bar's foot -> the magnet
local RELEASE_HEIGHT = 20
local RELEASE_GAP = 6 -- magnet -> the release hint

local HAULTRACK_TOP = HAULBUTTON_HEIGHT + HAULBUTTON_GAP
local HAULTRACK_HEIGHT = Dock.HAULPANEL_SIZE.Y.Offset
	- HAULTRACK_TOP
	- MAGNET_GAP
	- MAGNET_HEIGHT
	- RELEASE_GAP
	- RELEASE_HEIGHT

-- How fast the fill chases the server's value (1/seconds). The bar is smoothed rather
-- than snapped because drag is continuous and 10 Hz updates make a steady sink look
-- like a stutter; fast enough that a yank still lands as a visible jump.
local FILL_LERP_RATE = 14

type Contact = { dx: number, dz: number, rarity: string? }

local state = {
	inStage = false,
	hasSignal = false,
	radius = 0,
	contacts = {} :: { Contact },
	-- The player's world position at the moment the last contacts payload landed.
	-- Contact offsets are relative to it, so (origin + offset) is a contact's world
	-- point -- which is how contactRarityAt matches one to an aura. Snapshotted with
	-- the payload rather than read live so a walking player does not drag the match
	-- off the well between ticks.
	contactOrigin = nil :: Vector3?,
	rarityHint = nil :: string?,
	-- The nearest signal's "1 in N" find-rarity (Items.shownOdds). Sent on every
	-- detector now -- the old clarity gate on it is gone. Display flavour; nil only
	-- when there is no signal in range.
	oddsHint = nil :: number?,
	inRange = false,
	blocked = nil :: string?,
	-- Stages the soil outclasses the held magnet (0 = rated for it). Server-sent, read
	-- only to tint the haul bar warmer as the over-tier grind steepens -- it never
	-- blocks a haul and never becomes a status message.
	overGrip = 0,
	digProgress = 0,
	-- Committed to a signal and rooted in place. The server is the authority on this;
	-- the client never decides it is locked on its own, because being locked is what
	-- takes the player's movement away.
	locked = false,
}

local ui = {}
local blips: { Frame } = {}
-- What the fill is currently DRAWING, chasing state.digProgress. Separate from the
-- server's value so smoothing never feeds back into what we think progress is.
local shownProgress = 0

-- Pick-up billboard transition state. `lockGuiShown` is where the card is HEADED (set
-- the instant a show/hide starts); `lockGuiSettled` only turns true once the show tween
-- has finished, and it is what gates renderFrame's idle bob/shimmer so those never
-- fight the tween. The token lets a re-show that lands during a fade cancel the pending
-- "switch the billboard off".
local lockGuiShown = false
local lockGuiSettled = false
local lockGuiToken = 0
local lockHoldTween: Tween? = nil
-- When the player last clicked, in os.clock. Drives the button's kick animation and
-- nothing else -- "are they hauling" is answered by state.locked now, which comes from
-- the server, rather than by guessing from how recently a key was pressed.
local lastYankAt = -math.huge

-- ── Build ───────────────────────────────────────────────────────────

local function buildScope(parent: GuiObject)
	-- The radius ring. This is the stat you are buying, drawn at its actual size
	-- relative to the blips inside it, so a detector upgrade is legible on the HUD
	-- and not just in the shop.
	local edge = Instance.new("Frame")
	edge.Name = "RadiusRing"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.fromOffset(SCOPE_RADIUS * 2, SCOPE_RADIUS * 2)
	edge.BackgroundTransparency = 1
	edge.Parent = parent

	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(1, 0)
	edgeCorner.Parent = edge

	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Color = COLOR.scope
	edgeStroke.Transparency = 0.55
	edgeStroke.Thickness = 1
	edgeStroke.Parent = edge
	ui.edgeStroke = edgeStroke

	-- Half-radius ring, purely so distance on the scope is readable rather than just
	-- ordinal. Without it every blip is "somewhere in the circle".
	local inner = Instance.new("Frame")
	inner.Name = "HalfRing"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromOffset(SCOPE_RADIUS, SCOPE_RADIUS)
	inner.BackgroundTransparency = 1
	inner.Parent = parent

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = inner

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = COLOR.scope
	innerStroke.Transparency = 0.82
	innerStroke.Thickness = 1
	innerStroke.Parent = inner

	-- The sweep arm. One revolution per RANGE_RING_PERIOD, off the same clock as the
	-- range ring the detector throws on the ground, so the HUD and the world are
	-- visibly the same pulse rather than two unrelated animations.
	local arm = Instance.new("Frame")
	arm.Name = "SweepArm"
	arm.AnchorPoint = Vector2.new(0.5, 1)
	arm.Position = UDim2.fromScale(0.5, 0.5)
	arm.Size = UDim2.fromOffset(2, SCOPE_RADIUS)
	arm.BackgroundColor3 = COLOR.scope
	arm.BackgroundTransparency = 0.6
	arm.BorderSizePixel = 0
	arm.Parent = parent
	ui.arm = arm

	-- You. A fixed dot so the blips read as "relative to me" instantly.
	local origin = Instance.new("Frame")
	origin.Name = "Origin"
	origin.AnchorPoint = Vector2.new(0.5, 0.5)
	origin.Position = UDim2.fromScale(0.5, 0.5)
	origin.Size = UDim2.fromOffset(4, 4)
	origin.BackgroundColor3 = COLOR.text
	origin.BackgroundTransparency = 0.35
	origin.BorderSizePixel = 0
	origin.Parent = parent

	local originCorner = Instance.new("UICorner")
	originCorner.CornerRadius = UDim.new(1, 0)
	originCorner.Parent = origin

	-- Pooled. Contacts churn every tick as the player walks, and building and
	-- destroying twelve frames ten times a second to show the same twelve dots is
	-- pure garbage collection for no visible gain.
	for index = 1, MAX_BLIPS do
		local blip = Instance.new("Frame")
		blip.Name = `Blip{index}`
		blip.AnchorPoint = Vector2.new(0.5, 0.5)
		blip.Size = UDim2.fromOffset(8, 8)
		blip.BackgroundColor3 = COLOR.scope
		blip.BorderSizePixel = 0
		blip.Visible = false
		blip.ZIndex = 2
		blip.Parent = parent

		local blipCorner = Instance.new("UICorner")
		blipCorner.CornerRadius = UDim.new(1, 0)
		blipCorner.Parent = blip

		local blipStroke = Instance.new("UIStroke")
		blipStroke.Color = COLOR.panel
		blipStroke.Thickness = 1
		blipStroke.Parent = blip

		blips[index] = blip
	end
end

--- The pick-up prompt's whole face. The ProximityPrompt is Style = Custom, which means
--- Roblox renders NOTHING for it -- this billboard is the entire visual, wired to the
--- prompt through ProximityPromptService's Shown/Hidden/Hold events in start().
---
--- Custom style also drops the built-in mobile button and the gamepad glyph, so two
--- things here stand in for them: the whole card is a TextButton that drives
--- prompt:InputHoldBegin/End (without it the pick-up beat would be keyboard-and-gamepad
--- only -- the exact stranding the vanished dock button used to cause), and the keycap
--- text is swapped per input type on PromptShown.
---
--- NO CanvasGroup: its transparency does not render reliably inside a BillboardGui. The
--- fade in/out instead walks `fades` (instance, property, shown-value) and tweens each;
--- the UIScale on `card` does the landing bounce.
local function buildLockPromptGui(adornee: BasePart)
	local root = Instance.new("BillboardGui")
	root.Name = "PickupPrompt"
	root.Adornee = adornee
	-- Offset (pixels), not scale (studs), so the card holds a constant on-screen size
	-- for the whole 5-stud window it is up rather than ballooning as you close in. The
	-- extra 12px of height is bottom margin the pin pokes into.
	root.Size = UDim2.fromOffset(190, 76)
	root.StudsOffsetWorldSpace = Vector3.new(0, LOCKGUI_RISE, 0)
	root.AlwaysOnTop = true -- the signal is buried; the cue has to punch through the soil
	-- NO MaxDistance cap. It is measured CAMERA-to-adornee, not character-to-adornee, and
	-- a third-person camera sits 12-15+ studs behind the player (further if they zoom
	-- out) -- a cap near DIG_RADIUS hid the card outright while the player stood on the
	-- spot. Whether the card should show at all is already decided by the prompt's own
	-- MaxActivationDistance and updateLockPrompt's enable gate; this just has to draw.
	root.LightInfluence = 0
	root.Enabled = false
	root.Parent = adornee

	-- Everything visible lives under `card` so one UIScale bounces the lot; `hit` sits
	-- outside it so the tap target never moves or scales with the animation.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundTransparency = 1
	card.Parent = root

	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = card

	-- Pin: a square turned 45deg, sat behind the panel on its bottom edge so only the
	-- lower tip shows -- a downward arrow that plants the card on the spot.
	local pin = Instance.new("Frame")
	pin.Name = "Pin"
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.new(0.5, 0, 1, -12)
	pin.Size = UDim2.fromOffset(16, 16)
	pin.Rotation = 45
	pin.BackgroundColor3 = COLOR.panel
	pin.BackgroundTransparency = 1
	pin.BorderSizePixel = 0
	pin.ZIndex = 1
	pin.Parent = card

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0)
	panel.Size = UDim2.new(1, 0, 1, -12)
	panel.BackgroundColor3 = COLOR.panel
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = card

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UIKit.Radius.button
	panelCorner.Parent = panel

	local panelGrad = Instance.new("UIGradient")
	panelGrad.Rotation = 90
	panelGrad.Color = ColorSequence.new(Color3.fromHex("161C13"), COLOR.panel)
	panelGrad.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.Color = COLOR.scope
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = panel

	-- Keycap. Fills bottom-up with the signal colour across the hold -- the fill IS the
	-- hold timer, the same reading the haul panel's bar gives the mash.
	local keycap = Instance.new("Frame")
	keycap.Name = "Keycap"
	keycap.AnchorPoint = Vector2.new(0, 0.5)
	keycap.Position = UDim2.new(0, 12, 0.5, 0)
	keycap.Size = UDim2.fromOffset(46, 46)
	keycap.BackgroundColor3 = COLOR.empty
	keycap.BackgroundTransparency = 1
	keycap.BorderSizePixel = 0
	keycap.ClipsDescendants = true
	keycap.ZIndex = 3
	keycap.Parent = panel

	local keycapCorner = Instance.new("UICorner")
	keycapCorner.CornerRadius = UIKit.Radius.slot
	keycapCorner.Parent = keycap

	local keycapStroke = Instance.new("UIStroke")
	keycapStroke.Color = COLOR.scope
	keycapStroke.Transparency = 1
	keycapStroke.Thickness = 2
	keycapStroke.Parent = keycap

	local keycapFill = Instance.new("Frame")
	keycapFill.Name = "Fill"
	keycapFill.AnchorPoint = Vector2.new(0.5, 1)
	keycapFill.Position = UDim2.fromScale(0.5, 1)
	keycapFill.Size = UDim2.new(1, 0, 0, 0)
	keycapFill.BackgroundColor3 = COLOR.scope
	keycapFill.BackgroundTransparency = 1
	keycapFill.BorderSizePixel = 0
	keycapFill.ZIndex = 3
	keycapFill.Parent = keycap

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = UIKit.Font.title
	keyLabel.Text = "E"
	keyLabel.TextSize = 22
	keyLabel.TextColor3 = COLOR.text
	keyLabel.TextTransparency = 1
	keyLabel.TextStrokeTransparency = 1
	keyLabel.ZIndex = 4
	keyLabel.Parent = keycap

	-- One line, centred beside the keycap. There used to be a smaller label above this
	-- carrying the rarity ("LEGENDARY") or "BURIED SIGNAL"; dropped on request. The
	-- rarity still shows, quietly, as the accent colour on the stroke and the keycap.
	local action = UIKit.label(panel, {
		name = "Action",
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 68, 0.5, 0),
		size = UDim2.new(1, -80, 0, 28),
		font = UIKit.Font.title,
		textSize = 21,
		color = COLOR.scope,
		xAlign = Enum.TextXAlignment.Left,
		strokeTransparency = 1,
		zIndex = 3,
	})
	action.Text = "PICK UP"
	action.TextTransparency = 1

	-- The card is the touch (and mouse) target; see the header. Transparent, full-bleed,
	-- on top, and OUTSIDE `card` so the bounce never shifts it.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = 5
	hit.Parent = root

	return {
		root = root,
		card = card,
		scale = scale,
		pin = pin,
		panel = panel,
		stroke = stroke,
		keycap = keycap,
		keycapStroke = keycapStroke,
		keycapFill = keycapFill,
		keyLabel = keyLabel,
		action = action,
		hit = hit,
		-- (instance, property, value-when-shown) -- revealLockGui tweens each of these
		-- to its shown value on the way in and to 1 on the way out.
		--
		-- THE CARD IS GLASS ON PURPOSE. The fills sit near-transparent so the world
		-- (and the item breaking the surface) stays visible straight through it; what
		-- carries the card is the OUTLINE and the TEXT, not the panel. So the two
		-- strokes and both text labels still land at 0 while every BackgroundTransparency
		-- rests high -- drop the outline and the whole thing dissolves.
		fades = {
			{ pin, "BackgroundTransparency", 0.6 },
			{ panel, "BackgroundTransparency", 0.62 },
			{ stroke, "Transparency", 0.08 },
			{ keycap, "BackgroundTransparency", 0.5 },
			{ keycapStroke, "Transparency", 0 },
			{ keycapFill, "BackgroundTransparency", 0.3 },
			{ keyLabel, "TextTransparency", 0 },
			{ action, "TextTransparency", 0 },
		},
	}
end

--- A tiny horseshoe-magnet glyph, opening upward: a red "U" with two pale pole tips
--- — the same red-body / white-tips cliché build/Shops.luau's buildMagnetProp leans
--- on so the shape reads as "magnet" at a glance. Drawn from frames, no image asset,
--- like every other piece of HUD here. Returns the 30xMAGNET_DRAWN container for the
--- caller to place, wearing a UIScale of MAGNET_SCALE -- the pieces below are placed by
--- hand at fixed offsets, so a scale factor is how this grows without five sets of
--- coordinates having to be re-tuned in step. The caller reserves MAGNET_HEIGHT (the
--- SCALED height) for it; the UIScale pivots on the AnchorPoint, so a (0.5, 0) caller
--- gets growth straight down from where it placed the top.
local function buildMagnetIcon(parent: Instance): Frame
	local icon = Instance.new("Frame")
	icon.Name = "MagnetIcon"
	icon.Size = UDim2.fromOffset(30, MAGNET_DRAWN)
	icon.BackgroundTransparency = 1
	icon.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = MAGNET_SCALE
	scale.Parent = icon

	local function piece(name: string, x: number, y: number, w: number, h: number, color: Color3, radius: number?)
		local f = Instance.new("Frame")
		f.Name = name
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = icon
		if radius then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, radius)
			corner.Parent = f
		end
	end

	-- The curved back of the horseshoe: a rounded slab across the bottom, its two
	-- lower corners the magnet's arc. Then the two legs rising from it, then the pale
	-- tips capping them.
	piece("Bend", 1, 16, 28, 10, COLOR.red, 5)
	piece("LegLeft", 1, 2, 9, 16, COLOR.red)
	piece("LegRight", 20, 2, 9, 16, COLOR.red)
	piece("TipLeft", 1, 0, 9, 5, COLOR.text, 1)
	piece("TipRight", 20, 0, 9, 5, COLOR.text, 1)

	return icon
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DetectorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Radar scope: bottom-right corner, on the same INSTRUMENT_BOTTOM baseline as the
	-- rad meter diagonally opposite it, with the index button stacked above. It used
	-- to live inside the instrument band beside the dig button; out here it is clear
	-- of the screen's centre and no longer inflates the band's height for everything
	-- else. AnchorPoint(1,1) so the position places its bottom-RIGHT corner, which is
	-- what makes ROW_SIDE_MARGIN read as a margin from the screen edge.
	local dial, ring = UIKit.panel(gui, {
		name = "Scope",
		size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE),
		position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 1, -Dock.SCOPE_BOTTOM),
		anchorPoint = Vector2.new(1, 1),
		color = COLOR.panel,
		transparency = 0.25,
		cornerRadius = UIKit.Radius.pill,
		strokeColor = COLOR.stroke,
	})
	dial.ClipsDescendants = true
	ui.ring = ring

	buildScope(dial)

	ui.centre = UIKit.label(dial, {
		name = "Centre",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 53),
		size = UDim2.fromOffset(170, 22),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
	})

	-- Status line: dead centre, above the instrument band.
	ui.status = UIKit.label(gui, {
		name = "Status",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.STATUS_BOTTOM),
		size = UDim2.fromOffset(640, Dock.STATUS_HEIGHT),
		font = UIKit.Font.body,
		textSize = 18,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- ── The lock-on prompt ────────────────────────────────────────────
	-- A ProximityPrompt over the glow itself, so the cue to commit is AT THE SPOT you
	-- magnet the item rather than in a caption at the bottom of the screen.
	--
	-- Roblox's own prompt rather than a hand-rolled billboard, and it is not laziness:
	-- HoldDuration gives the hold-to-commit and its fill ring for free, and the prompt
	-- brings its own mobile button and gamepad glyph. That last part is what lets the
	-- dock button go away without stranding touch players.
	--
	-- IT IS CLIENT-OWNED, PARENTED TO OUR OWN HOLDER PART, for two reasons that both
	-- rule out putting it on the aura itself:
	--   * auras are PUBLIC server parts. A prompt on one would offer HOLD E to players
	--     whose detector cannot register that signal — the gates are per-player, the
	--     glow is not.
	--   * auras are destroyed the moment their signal is pulled, which would take a
	--     prompt parented to one with it, mid-haul.
	-- A part we own and move ourselves sidesteps both.
	local holder = Instance.new("Part")
	holder.Name = "LockPromptHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Parent = Workspace
	ui.promptHolder = holder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Buried Signal"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = LOCK_HOLD_SECONDS
	-- Style = Custom: Roblox draws no prompt UI at all, we render our own billboard
	-- (buildLockPromptGui) off ProximityPromptService's events in start(). The prompt
	-- object still owns all the INPUT -- key, gamepad button, hold timing, the Triggered
	-- fire -- so none of that logic moves; only the face changes.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	-- The item is buried and the aura hugs the ground, so a sight test flickers as the
	-- camera moves. Range is already gated by the server's own inRange below.
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Tuning.DIG_RADIUS
	prompt.Enabled = false
	prompt.Parent = holder
	ui.prompt = prompt
	ui.lockGui = buildLockPromptGui(holder)

	-- NO DIG BUTTON HERE ANY MORE. It used to sit dead centre of the instrument band,
	-- on screen for the whole time you were in a stage, saying GET CLOSER while you
	-- walked — permanent furniture for something that only matters in the few seconds
	-- you are stood on a glow, directly above the hotbar it competed with. Locking on
	-- is the world prompt over the glow now (see the lock prompt further down), and
	-- the haul panel carries the mash bar. The dock has no dig widget at all.

	-- Unearth banner: true centre, upper-third of the screen. Already lived there
	-- before this pass; only the size and type grew.
	local banner, bannerStroke = UIKit.panel(gui, {
		name = "Banner",
		size = UDim2.fromOffset(640, 160),
		position = UDim2.fromScale(0.5, 0.32),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = COLOR.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	ui.banner = banner
	ui.bannerStroke = bannerStroke

	ui.bannerRarity = UIKit.label(banner, {
		name = "Rarity",
		position = UDim2.fromOffset(0, 14),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerName = UIKit.label(banner, {
		name = "NameLabel", -- NOT "Name" — every Instance already has a .Name
		-- property, so a child actually named "Name" is unreachable by
		-- Banner.Name (that resolves to the property, a string, not the child).
		-- Harmless here since every reader uses the captured ui.bannerName
		-- reference, never a re-lookup, but it is a landmine for anyone who
		-- later does try to reach it by path.
		position = UDim2.fromOffset(0, 40),
		size = UDim2.new(1, 0, 0, 50),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero - 4,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerFlavor = UIKit.label(banner, {
		name = "Flavor",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 96),
		size = UDim2.new(1, -40, 0, 50),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})

	-- ── The haul panel ────────────────────────────────────────────────
	-- Up only while locked onto a signal. This is the second beat of the pull: the
	-- first tap commits you to one buried thing and plants your feet, and everything
	-- from there happens in here.
	--
	-- It sits right above the hotbar rather than at screen centre, so the item climbing
	-- out of the soil stays visible above it. The whole reason the haul is a physical
	-- model in the world rather than a number is that you get to watch it surface; a
	-- panel over the middle of the screen would hide exactly that. Anchored off
	-- Dock.HAULPANEL_BOTTOM -- see that constant for where "right above the hotbar" puts
	-- it and why it is left to overlay the (left-anchored) instrument band.
	-- A BARE FRAME, NOT UIKit.panel. Nothing is drawn for the container itself -- no
	-- fill, no corner, no stroke -- it exists only to place the stack as a unit and to
	-- be shown and hidden in one line. See the constants block for why the slab went.
	local haul = Instance.new("Frame")
	haul.Name = "HaulPanel"
	haul.Size = Dock.HAULPANEL_SIZE
	-- BOTTOM-RIGHT, not bottom-centre: centred put this straight over the item climbing
	-- out of the soil, which is the one thing a haul is for looking at. Anchor (1,1) so
	-- the position places its bottom-RIGHT corner, which is what makes HAULPANEL_RIGHT
	-- read as an inset from the screen edge -- see that constant for why right and not
	-- left, and for what happens on a viewport too narrow to dodge centre at all.
	haul.Position = UDim2.new(1, -Dock.HAULPANEL_RIGHT, 1, -Dock.HAULPANEL_BOTTOM)
	haul.AnchorPoint = Vector2.new(1, 1)
	haul.BackgroundTransparency = 1
	haul.BorderSizePixel = 0
	haul.Visible = false
	haul.Parent = gui
	ui.haul = haul

	-- PULL SITS ON TOP OF THE BAR, which is the whole reading order of the widget: the
	-- verb, then the column it fills, then the magnet doing the filling. It is a real
	-- button and not a key hint because a phone has no E key -- without a tappable
	-- control here the entire second beat would be keyboard-only. It keeps its own fill
	-- and stroke now that there is no panel behind it to sit on.
	local haulButton, haulButtonStroke = UIKit.button(haul, {
		name = "HaulButton",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromOffset(HAULBAR_MID, HAULBUTTON_HEIGHT / 2),
		size = UDim2.fromOffset(HAULBAR_COL, HAULBUTTON_HEIGHT),
		-- BOLD, NOT BLACK. UIKit.Font's header reserves `hero` for "short, one-off,
		-- celebratory strings" and puts primary buttons on `title` -- and PULL is the
		-- single most repeated control in the game, hammered dozens of times per haul,
		-- which is the exact opposite of one-off. GothamBlack also gains almost nothing
		-- here: it measures 2px wider than Bold at this size, so all it bought was a
		-- broken rule and slightly mushier counters at speed.
		font = UIKit.Font.title,
		textSize = HAULBUTTON_TEXT,
		color = COLOR.green,
		fillColor = COLOR.panel,
		-- NEARLY OPAQUE, where every other fill in the kit is a translucent 0.15-0.2.
		-- Green text on a fill that lets the ground through is green on green the
		-- moment a player is standing on grass, which is most of the time -- at 0.2
		-- this was the least readable thing in the widget despite being the largest.
		-- It needs a plate of its own now that there is no panel supplying one.
		fillTransparency = 0.05,
		strokeColor = COLOR.stroke,
		strokeThickness = UIKit.Stroke.normal,
		cornerRadius = UIKit.Radius.button,
		text = "PULL",
	})
	-- NO TEXT STROKE, unlike every other line in this widget. Those need one because
	-- they sit on open terrain; this one has a near-opaque plate right behind it, and
	-- an outline on top of that only fattens the glyphs into each other.
	ui.haulButton = haulButton
	ui.haulButtonStroke = haulButtonStroke

	-- THE BAR. The fill is bottom-anchored and grows UPWARD, so winning is getting it
	-- to the top edge -- the same direction the item is actually travelling through the
	-- soil. That is the whole point of the rotation: a strip filling rightwards was a
	-- progress bar attached to a haul, this is a picture of the haul. It is what the
	-- player stares at while mashing, so it takes every pixel of height the stack does
	-- not spend on the rows around it (HAULTRACK_HEIGHT).
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromOffset(HAULBAR_MID, HAULTRACK_TOP)
	track.Size = UDim2.fromOffset(HAULTRACK_WIDTH, HAULTRACK_HEIGHT)
	track.BackgroundColor3 = COLOR.empty
	track.BorderSizePixel = 0
	track.Parent = haul

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UIKit.Radius.button
	trackCorner.Parent = track

	-- THE EMPTY COLUMN HAS TO BE VISIBLE, which the horizontal bar never needed. On a
	-- strip the eye reads the fill's leading edge and infers the rest; on a column the
	-- fill is at the BOTTOM and the whole point is the distance still above it, so
	-- COLOR.empty on its own left the target invisible -- you could see how far you had
	-- come and not how far was left.
	--
	-- IT IS ALSO WHERE THE RARITY ACCENT LIVES NOW. That used to be the panel's stroke,
	-- and the panel is gone; this is the only outline left, and tinting the vessel you
	-- are filling is a better home for the colour than the slab around it ever was.
	-- THICK. This outline is doing three jobs at once -- it separates the empty column
	-- from whatever terrain is behind it, it is the only frame the widget has left, and
	-- it is where the rarity colour lives -- so it is the one line on screen that most
	-- deserves the weight. It has climbed thin(2) -> normal(3) -> thick(4) as each of
	-- those jobs landed on it.
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = COLOR.stroke
	trackStroke.Thickness = UIKit.Stroke.thick
	trackStroke.Parent = track
	ui.haulStroke = trackStroke

	-- ANCHORED TO THE TRACK'S FLOOR (anchor 0,1 pinned at scale-y 1), which is what
	-- makes the height renderFrame writes read as a column rising rather than a lid
	-- dropping. Get this wrong and the bar drains from the top while the item climbs --
	-- the two would say opposite things about the same haul.
	local haulFill = Instance.new("Frame")
	haulFill.Name = "Fill"
	haulFill.AnchorPoint = Vector2.new(0, 1)
	haulFill.Position = UDim2.fromScale(0, 1)
	haulFill.Size = UDim2.fromScale(1, 0)
	haulFill.BackgroundColor3 = COLOR.green
	haulFill.BorderSizePixel = 0
	haulFill.Parent = track
	ui.haulFill = haulFill

	local haulFillCorner = Instance.new("UICorner")
	haulFillCorner.CornerRadius = UIKit.Radius.button
	haulFillCorner.Parent = haulFill

	-- UNDER THE BAR'S FOOT: the magnet doing the pulling. It is in the position it is
	-- actually working from, and everything above it is what it has left to drag up.
	local magnet = buildMagnetIcon(haul)
	magnet.AnchorPoint = Vector2.new(0.5, 0)
	magnet.Position = UDim2.fromOffset(HAULBAR_MID, HAULTRACK_TOP + HAULTRACK_HEIGHT + MAGNET_GAP)

	-- RELEASE HAS TO BE VISIBLE. Locking roots the character, so a player who cannot
	-- find the way out is stuck standing in a field. It is a real button rather than
	-- only a key hint for the same reason PULL is: on touch there is no Q. Under the
	-- magnet, at the foot of the stack -- as far from the mash button as the widget can
	-- put it, because these two are the only controls here and hitting the wrong one
	-- ends the haul.
	--
	-- No outline and no fill: this is a quiet way out, not a second call to action. It
	-- is also the only text with nothing behind it, so it takes a text stroke to stay
	-- legible over bright ground.
	local releaseButton = UIKit.button(haul, {
		name = "ReleaseButton",
		anchorPoint = Vector2.new(0.5, 0),
		size = UDim2.fromOffset(HAULBAR_COL, RELEASE_HEIGHT),
		position = UDim2.fromOffset(
			HAULBAR_MID,
			HAULTRACK_TOP + HAULTRACK_HEIGHT + MAGNET_GAP + MAGNET_HEIGHT + RELEASE_GAP
		),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = COLOR.dim,
		fillColor = COLOR.panel,
		fillTransparency = 1,
		strokeThickness = 0,
		cornerRadius = UIKit.Radius.button,
		text = "Q  to release",
	})
	releaseButton.TextStrokeTransparency = 0.2
	ui.releaseButton = releaseButton

	-- BESIDE THE BAR: what the detector reads about the thing you locked onto. Beside
	-- rather than above, because a readout stacked over the bar would cost the stack
	-- two more rows of height and this widget has none to spare -- the column to the
	-- right is empty anyway. Level with the TOP of the track, which is the mark you are
	-- pulling towards.
	--
	-- Two lines: the rarity word is the headline and carries the accent tint (in step
	-- with the track's stroke), the odds sit under it, quiet. Both land on any detector
	-- (DigService.hintFor is no longer clarity-gated). Both take a text stroke -- with
	-- the panel gone this text can end up over sunlit sludge.
	ui.haulTitle = UIKit.label(haul, {
		name = "Title",
		position = UDim2.fromOffset(HAULCOL_X, HAULTRACK_TOP - 4),
		size = UDim2.fromOffset(HAULCOL_WIDTH, 30),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		color = COLOR.scope,
		strokeTransparency = 0.15,
	})

	-- body(15), not caption(13), and a near-opaque text stroke. Quiet is the intent --
	-- the rarity word is the headline and this is its footnote -- but caption grey with
	-- a soft stroke, over sunlit ground and with no panel behind it, was not quiet, it
	-- was illegible. Held one step below the rarity in size and colour instead, which
	-- keeps the hierarchy without giving up the readout.
	ui.haulOdds = UIKit.label(haul, {
		name = "Odds",
		position = UDim2.fromOffset(HAULCOL_X, HAULTRACK_TOP + 28),
		size = UDim2.fromOffset(HAULCOL_WIDTH, 22),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = COLOR.dim,
		strokeTransparency = 0.15,
	})

	-- A question mark, IN THE RARITY WORD'S OWN SLOT. You committed to a lump in the
	-- dirt; whether you get to know what it is is the detector's job, not this widget's.
	-- Hidden the moment the rarity resolves -- the two share one rectangle, and
	-- "LEGENDARY" next to a "?" reads as a bug.
	ui.haulQuestion = UIKit.label(haul, {
		name = "HaulQuestion",
		position = UDim2.fromOffset(HAULCOL_X, HAULTRACK_TOP - 4),
		size = UDim2.fromOffset(HAULCOL_WIDTH, 30),
		font = UIKit.Font.hero,
		textSize = 30,
		color = COLOR.dim,
		strokeTransparency = 0.15,
		text = "?",
	})

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function signalColor(): Color3
	if state.rarityHint then
		local def = Rarity.DEFS[state.rarityHint]
		if def then
			return def.color
		end
	end
	return COLOR.scope
end

--- Contacts arrive as WORLD-space offsets from the player. The scope is drawn in
--- camera space so "up" is wherever the player is looking — a radar that stays
--- locked to world north forces the player to do the rotation in their head, every
--- frame, forever.
---
--- The sign convention here is the needle's, kept deliberately: an angle measured
--- from the camera's look direction maps straight onto clockwise-from-up, which is
--- what both the old Rotation property and this offset use.
local function renderBlips()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local look = camera.CFrame.LookVector
	local cameraYaw = math.atan2(look.Z, look.X)
	local radius = if state.radius > 0 then state.radius else 1

	for index = 1, MAX_BLIPS do
		local blip = blips[index]
		local contact = state.contacts[index]

		if contact == nil then
			blip.Visible = false
			continue
		end

		local distance = math.sqrt(contact.dx * contact.dx + contact.dz * contact.dz)
		local relative = math.atan2(contact.dz, contact.dx) - cameraYaw
		-- Clamped, not hidden: a contact fractionally outside the ring because the
		-- player moved between ticks should sit ON the ring, not blink out.
		local reach = math.min(distance / radius, 1) * SCOPE_RADIUS

		blip.Position = UDim2.new(0.5, math.sin(relative) * reach, 0.5, -math.cos(relative) * reach)

		local def = if contact.rarity then Rarity.DEFS[contact.rarity] else nil
		blip.BackgroundColor3 = if def then def.color else COLOR.scope

		-- The nearest contact is the one every other part of the HUD is talking
		-- about, so it is drawn bigger. Without this the scope reads as a cloud and
		-- the status line appears to be describing an arbitrary member of it.
		local lead = index == 1
		blip.Size = UDim2.fromOffset(if lead then 11 else 7, if lead then 11 else 7)
		blip.Visible = true
	end
end

local function renderFrame(dt: number)
	local colour = signalColor()

	renderBlips()

	-- One revolution per pulse period, sharing os.clock with FieldController's ground
	-- ring so the two land together without either one owning the other's timing.
	local phase = (os.clock() % Tuning.RANGE_RING_PERIOD) / Tuning.RANGE_RING_PERIOD
	ui.arm.Rotation = phase * 360
	ui.arm.BackgroundTransparency = if state.inStage then 0.6 else 0.9

	ui.ring.Color = if state.hasSignal then colour else COLOR.stroke
	ui.edgeStroke.Color = if state.hasSignal then colour else COLOR.scope

	-- Chase rather than snap. Exponential so it converges at the same visual rate
	-- whatever the framerate -- the naive `+= (target - shown) * rate * dt` overshoots
	-- and oscillates the moment dt gets large, which on a bar the player is staring at
	-- while mashing is very visible.
	shownProgress += (state.digProgress - shownProgress) * (1 - math.exp(-FILL_LERP_RATE * dt))
	-- HEIGHT, not width -- the bar is a column and the fill is pinned to its floor
	-- (see build), so progress is how far up the track the item has climbed.
	ui.haulFill.Size = UDim2.fromScale(1, math.clamp(shownProgress, 0, 1))

	-- The kick: one ease-out swell per yank, driven off the local timestamp so it
	-- starts on the same frame the key went down. It moved from the dock button (now
	-- gone) onto the haul panel's own mash button, which is where the player's eyes
	-- and finger both are during a haul. Still reports the INPUT, never the outcome --
	-- it confirms a click happened, it does not promise the server honoured it.
	local sinceYank = os.clock() - lastYankAt
	local kick = if sinceYank < YANK_KICK_SECONDS then (1 - sinceYank / YANK_KICK_SECONDS) ^ 2 else 0
	ui.haulButton.Size =
		UDim2.fromOffset(HAULBAR_COL, math.floor(HAULBUTTON_HEIGHT * (1 + kick * YANK_KICK_SCALE)))

	-- The pick-up card's idle life: a slow hover, and a stroke that breathes on the
	-- aura's OWN pulse period so the card, the ground ring and the scope arm all beat
	-- together. Only once the show tween has settled -- before that revealLockGui owns
	-- both the offset and the stroke.
	if lockGuiShown and lockGuiSettled then
		local t = os.clock()
		local g = ui.lockGui
		g.root.StudsOffsetWorldSpace = Vector3.new(0, LOCKGUI_RISE + math.sin(t * 2.6) * 0.12, 0)
		local pulse = 0.5 + 0.5 * math.sin(t * (2 * math.pi / Tuning.RANGE_RING_PERIOD))
		g.stroke.Transparency = 0.05 + 0.22 * pulse
	end
end

--- Fade + bounce the whole card in or out. Idempotent: called from the prompt's
--- Shown/Hidden events, which already only fire on a real transition, but the guard
--- keeps a double-fire from restarting the tween.
local function revealLockGui(shown: boolean)
	if shown == lockGuiShown then
		return
	end
	lockGuiShown = shown
	lockGuiSettled = false
	lockGuiToken += 1
	local token = lockGuiToken
	local g = ui.lockGui
	local info = if shown then LOCKGUI_SHOW_TWEEN else LOCKGUI_HIDE_TWEEN

	if shown then
		g.root.Enabled = true
		g.scale.Scale = 0.7
		g.keycapFill.Size = UDim2.new(1, 0, 0, 0)
	elseif lockHoldTween then
		lockHoldTween:Cancel()
		lockHoldTween = nil
	end

	local scaleGoal = if shown then 1 else 0.7
	TweenService:Create(g.scale, info, { Scale = scaleGoal }):Play()
	for _, f in g.fades do
		local goal = if shown then f[3] else 1
		TweenService:Create(f[1], info, { [f[2]] = goal }):Play()
	end

	-- The tail: the LAST transition of the pair gets to finish the job. A newer one
	-- bumps the token and this no-ops.
	task.delay(info.Time, function()
		if token ~= lockGuiToken then
			return
		end
		if lockGuiShown then
			lockGuiSettled = true
		else
			g.root.Enabled = false
		end
	end)
end

--- Keycap fill = the hold clock. Runs to full over exactly HoldDuration so it tops out
--- on the frame the prompt Triggers; a release before then drains it back.
local function setLockHold(holding: boolean)
	local g = ui.lockGui
	if lockHoldTween then
		lockHoldTween:Cancel()
		lockHoldTween = nil
	end
	if holding then
		lockHoldTween = TweenService:Create(
			g.keycapFill,
			TweenInfo.new(ui.prompt.HoldDuration, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(1, 0, 1, 0) }
		)
		lockHoldTween:Play()
	else
		TweenService:Create(g.keycapFill, TweenInfo.new(0.1), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	end
end

--- Park the lock prompt on the glow the player is standing over, or switch it off.
--- Driven from renderState (10 Hz, on SweepState) rather than per frame: the tagged
--- set is small, but there is no reason to walk it sixty times a second.
---
--- Gated on exactly what sendLock used to check. `not state.locked` is the important
--- one -- see the E-key note on pressPull: while a prompt is enabled it also swallows
--- E for its own hold, so leaving it on during a haul would fight the mash.
local function updateLockPrompt()
	local offerable = state.inStage and state.inRange and not state.locked and state.blocked ~= "full"
	if not offerable then
		ui.prompt.Enabled = false
		return
	end

	-- Auras are tagged Models with a Core part (build/SignalAura); FieldController
	-- enumerates them the same way. Nearest one wins, which matches the server's own
	-- choice of target -- it hauls whatever contact is closest.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		ui.prompt.Enabled = false
		return
	end

	local best, bestDist = nil, math.huge
	for _, aura in CollectionService:GetTagged(Tuning.AURA_TAG) do
		local core = aura:FindFirstChild("Core")
		if core and core:IsA("BasePart") then
			local delta = core.Position - root.Position
			local flat = delta.X * delta.X + delta.Z * delta.Z
			if flat < bestDist then
				best, bestDist = core, flat
			end
		end
	end

	if best == nil then
		ui.prompt.Enabled = false
		return
	end

	ui.promptHolder.Position = best.Position

	-- The card carries no rarity text any more, but the accent still does: the rarity
	-- colour on the stroke and keycap (any detector reads it now), scope blue only in
	-- the frame before it resolves. Cheap, and the hint can change under the card, so
	-- set it every tick.
	local accent = signalColor()
	ui.prompt.ObjectText = if state.rarityHint then string.upper(state.rarityHint) else "Buried Signal"
	ui.lockGui.action.TextColor3 = accent
	ui.lockGui.stroke.Color = accent
	ui.lockGui.keycapStroke.Color = accent
	ui.lockGui.keycapFill.BackgroundColor3 = accent

	ui.prompt.Enabled = true
end

local function renderState()
	updateLockPrompt()

	-- THE PANEL IS DRIVEN OFF THE SERVER'S `locked`, NOT off anything the client
	-- decided. Every release path lives on the server (bag full, signal gone, blackout,
	-- item surfaced), so the panel closing is always downstream of the lock actually
	-- being dropped -- it can never linger over a lock the server has already let go
	-- of, and it can never hide one that is still holding the player's feet.
	ui.haul.Visible = state.locked
	if state.locked then
		-- The BAR'S OUTLINE carries the rarity colour (any detector now), scope blue
		-- only in the brief frame before it resolves -- it took this over from the
		-- panel stroke when the panel went. The "?" beside the bar is that unresolved
		-- state at rest; this is it in colour.
		local accent = signalColor()
		ui.haulStroke.Color = accent

		-- The readout spells out what the stroke's colour only implies: the rarity word
		-- (state.rarityHint) and the "1 in N" odds (state.oddsHint), both on any
		-- detector now -- exactly what DigService.hintFor sent. Two labels stacked
		-- beside the bar rather than one joined line, so a long rarity and a six-figure
		-- odds never have to share a row this narrow.
		--
		-- THE ODDS FOLLOW THE RARITY, not their own hint. They are the odds OF the
		-- rarity above them; printing "1 in 50k" under a blank headline would be a
		-- number with nothing to attach to, so the "?" branch clears both.
		if state.rarityHint then
			ui.haulTitle.Text = string.upper(state.rarityHint)
			ui.haulOdds.Text = if state.oddsHint then Items.oddsText(state.oddsHint) else ""
		else
			ui.haulTitle.Text = ""
			ui.haulOdds.Text = ""
		end
		ui.haulTitle.TextColor3 = accent
		ui.haulQuestion.Visible = not state.rarityHint
		-- An under-rated magnet still locks on, still pulls, and is never told it is too
		-- weak -- the grind says it. All the panel does is warm the bar as the soil
		-- outclasses the magnet: green when rated, amber one stage over, red by three.
		local strain = math.clamp(state.overGrip, 0, 3)
		local fill
		if strain <= 1 then
			fill = COLOR.green:Lerp(COLOR.amber, strain)
		else
			fill = COLOR.amber:Lerp(COLOR.red, (strain - 1) / 2)
		end
		ui.haulFill.BackgroundColor3 = fill
		ui.haulButton.Text = "PULL"
		ui.haulButton.TextColor3 = if strain > 0 then fill else COLOR.green
		-- The button's outline takes the strain colour with its text. This is the one
		-- field on ui that was captured and never read; lighting it up costs nothing
		-- and makes the control the player is hammering the loudest thing in the
		-- widget, which out in the corner it now lives in it needs to be.
		ui.haulButtonStroke.Color = if strain > 0 then fill else COLOR.green
	end

	if not state.inStage then
		-- BLANK, AND THE BUTTON GOES WITH IT. Out of a stage means you are in the plaza
		-- shopping, banking or racking. A status line telling you that you cannot dig
		-- on the shop floor, and a PULL button that does nothing when pressed, are
		-- both noise printed over the top of whatever panel you actually came here to
		-- use — and between them they are what stopped the station panel from being
		-- able to sit at screen centre. Every other branch below still speaks,
		-- because every other branch is about a stage you are standing in.
		--
		-- The button costs nothing to lose here: it is inert out of a stage (the
		-- server has no signal to give), and E still works, so nothing is unreachable
		-- — it reappears the moment you step onto sludge, which is also the moment it
		-- starts meaning something.
		--
		-- The SCOPE stays, unlike the button. It is the detector itself rather than a
		-- verb attached to it, it now lives out in the corner where it is not in the
		-- way of anything, and a dial that vanished every time you walked into the
		-- plaza would read as broken hardware rather than as a quiet one.
		ui.status.Text = ""
		ui.centre.Text = ""
		return
	end

	ui.centre.Text = `{math.floor(state.radius + 0.5)} stud sweep`
	ui.centre.TextColor3 = COLOR.dim

	if not state.hasSignal then
		-- Standing in a glow that somebody else's detector put there. This is a real
		-- state, not an error: auras are public, the depth gate is not.
		if state.blocked == "unregistered" then
			ui.status.Text = "that signal is buried too deep for your detector"
			ui.status.TextColor3 = COLOR.red
			return
		end

		-- Detector on, nothing revealed in range. The old "sweeping… nothing in
		-- range" status line was removed on request -- the empty scope says it.
		ui.status.Text = ""
		return
	end

	if state.blocked == "full" then
		ui.status.Text = "bag is full"
		ui.status.TextColor3 = COLOR.red
	else
		-- Nothing else left for the bottom line to say: out of reach, the glow on the
		-- ground is the only cue (the dock's GET CLOSER button is gone with the rest of
		-- the dig widget); in reach but not locked, updateLockPrompt already has the
		-- floating PICK UP card up over the glow with the rarity/odds; locked, the haul
		-- panel's own title carries them. "you are standing on it" used to repeat
		-- whichever of those was already on screen.
		ui.status.Text = ""
	end
end

-- ── Banner ──────────────────────────────────────────────────────────

local bannerToken = 0

--- "0.05 kg" / "12 kg" / "220 kg" — two sig figs under a kilo, whole numbers above.
--- Small dup of IndexController.formatWeight (the 2nd caller); lift to UIKit on a 3rd.
local function formatWeight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

local function showUnearthed(found)
	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else COLOR.text

	local modifier = if found.modifier == "None" then "" else found.modifier .. " "
	local heft = if type(found.weight) == "number" then `  \u{00B7}  {formatWeight(found.weight)}` else ""
	ui.bannerRarity.Text = string.upper(modifier .. found.rarity) .. heft
	ui.bannerRarity.TextColor3 = colour
	ui.bannerName.Text = found.name
	ui.bannerFlavor.Text = found.flavor
	ui.bannerStroke.Color = colour
	ui.banner.Visible = true

	bannerToken += 1
	local token = bannerToken
	task.delay(3.5, function()
		if token == bannerToken then
			ui.banner.Visible = false
		end
	end)
end

-- ── Input ───────────────────────────────────────────────────────────

local digYank: any = nil
local digLock: any = nil

--- One click, one yank. There is deliberately NO local rate limit and no debounce
--- here: the server's token bucket is the authority on what counts, and a second
--- limiter on the client would only ever disagree with it -- quietly eating clicks
--- the server would have honoured, which reads as input lag on a verb whose whole
--- appeal is that it answers instantly.
local function sendYank()
	if not state.locked then
		return
	end

	lastYankAt = os.clock()
	digYank:FireServer()
	renderState()
end

--- Commit to whatever we are standing on. The server picks the actual signal; all this
--- says is "yes, this one". Called ONLY from the world prompt's Triggered, which fires
--- after the hold completes -- see pressPull for why nothing else may call it.
local function sendLock()
	if not state.inStage or not state.inRange or state.locked or state.blocked == "full" then
		return
	end
	digLock:FireServer(true)
end

--- Give up the haul. NEVER gated on client state: this is the only way out of a lock
--- that has rooted the character, so it fires unconditionally and lets the server
--- decide whether there was anything to release. A client-side `if` in front of this
--- is a way for a player to get stuck standing in a field.
local function sendRelease()
	digLock:FireServer(false)
end

--- E while hauling. YANK-ONLY, and the missing "else lock on" branch is load-bearing.
---
--- ProximityPrompt does NOT mark its key input as game-processed, so InputBegan still
--- sees E while the prompt is up. If this also locked on, a single tap would commit
--- instantly and the hold would never mean anything -- the whole point of the change.
--- So the prompt is the only thing that may call sendLock, and this only ever yanks.
---
--- The two can never both be live: updateLockPrompt disables the prompt the moment the
--- player is locked, which is also what stops E re-triggering it mid-mash.
local function pressPull()
	if state.locked then
		sendYank()
	end
end

-- ── Lifecycle ────────────────────────────────────────────────────────

--- Read by FieldController so the ground ring is drawn at the radius the server
--- actually resolved, rather than the client guessing from its own gear numbers —
--- perks fold into detectorRadius and only StatResolver knows the answer.
function Detector.radius(): number
	return if state.inStage then state.radius else 0
end

--- The rarity of THIS client's own roll for the contact under a given world point, or
--- nil when there is no contact there. FieldController reads this to tint each aura
--- well per-player: the aura part is shared but the roll is per-player (signal X can
--- be Rare for one player, Common for the next), so the rarity cannot live on the
--- part — it rides this client-only payload, the same place the radar blips get it.
--- No longer clarity-gated: every detector colours its wells now (DigService.hintFor).
---
--- Matched by position because the payload deliberately carries no signal id. The
--- tolerance covers the drift between the server's snapshot of the player (which the
--- offsets are measured from) and where the client has walked since; wells sit tens
--- of studs apart, so it cannot bind the wrong one.
local CONTACT_MATCH_TOLERANCE = 4 -- studs

function Detector.contactRarityAt(worldPosition: Vector3): string?
	local origin = state.contactOrigin
	if origin == nil or not state.inStage then
		return nil
	end
	for _, contact in state.contacts do
		if contact.rarity ~= nil then
			local dx = (origin.X + contact.dx) - worldPosition.X
			local dz = (origin.Z + contact.dz) - worldPosition.Z
			if dx * dx + dz * dz <= CONTACT_MATCH_TOLERANCE * CONTACT_MATCH_TOLERANCE then
				return contact.rarity
			end
		end
	end
	return nil
end

function Detector.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	digYank = Net.get("DigYank")
	digLock = Net.get("DigLock")

	Net.get("SweepState").OnClientEvent:Connect(function(payload)
		state.inStage = payload.inStage == true
		state.hasSignal = payload.hasSignal == true
		state.radius = payload.radius or 0
		state.contacts = payload.contacts or {}
		-- Snapshot where the player is now, so FieldController can turn each contact
		-- offset back into a world point and match it to an aura well (contactRarityAt).
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			state.contactOrigin = root.Position
		end
		state.rarityHint = payload.rarityHint
		state.oddsHint = payload.oddsHint
		state.inRange = payload.inRange == true
		state.blocked = payload.blocked
		state.overGrip = payload.overGrip or 0
		state.digProgress = payload.digProgress or 0
		state.locked = payload.locked == true
		-- payload.carrying / payload.capacity are deliberately ignored: the hotbar
		-- (InventoryController, fed by CarryState) is the authority on the bag now,
		-- and two widgets answering "how full am I" from two different remotes is how
		-- they end up disagreeing by a tick. payload.strength / payload.newContacts
		-- too, since the audio cues they fed are gone.
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(function(found)
		showUnearthed(found)
	end)

	-- InputBegan only, and no InputEnded partner. Roblox does not auto-repeat a held
	-- key through InputBegan, so holding E down yields exactly one yank -- which is
	-- precisely the behaviour this feature wants. Nothing has to suppress the hold;
	-- the platform already does.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			pressPull()
		elseif input.KeyCode == Enum.KeyCode.Q then
			sendRelease()
		end
	end)

	-- ── The pick-up prompt ──────────────────────────────────────────────
	-- Style = Custom, so ui.lockGui is the whole face and these events drive it. The
	-- prompt object still owns the input; nothing here decides when to lock on except
	-- its Triggered, which fires once after the hold completes (see pressPull for why
	-- nothing else may call sendLock).
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt ~= ui.prompt then
			return
		end
		-- Custom style also drops the gamepad glyph and the touch button, so the keycap
		-- says what THIS player presses. Default GamepadKeyCode for a prompt is ButtonX.
		if inputType == Enum.ProximityPromptInputType.Touch then
			ui.lockGui.keyLabel.Text = "HOLD"
			ui.lockGui.keyLabel.TextSize = 13
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			ui.lockGui.keyLabel.Text = "X"
			ui.lockGui.keyLabel.TextSize = 22
		else
			ui.lockGui.keyLabel.Text = "E"
			ui.lockGui.keyLabel.TextSize = 22
		end
		revealLockGui(true)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt ~= ui.prompt then
			return
		end
		revealLockGui(false)
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt == ui.prompt then
			setLockHold(true)
		end
	end)

	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if prompt == ui.prompt then
			setLockHold(false)
		end
	end)

	ui.prompt.Triggered:Connect(function()
		-- Snap the fill full on the frame it commits, then a tiny pop. Almost always the
		-- server's `locked` comes straight back and PromptHidden fades the whole card
		-- out; the delayed settle only matters if the lock is somehow refused and the
		-- card stays up -- it should not sit there frozen mid-pop.
		ui.lockGui.keycapFill.Size = UDim2.new(1, 0, 1, 0)
		TweenService:Create(ui.lockGui.scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
		sendLock()
		task.delay(0.16, function()
			if lockGuiShown then
				TweenService:Create(ui.lockGui.scale, TweenInfo.new(0.16), { Scale = 1 }):Play()
				setLockHold(false)
			end
		end)
	end)

	-- Custom style means Roblox draws no mobile tap button, so the card itself is one:
	-- a press drives the prompt's own hold, and its release -- or the pointer leaving the
	-- card mid-press, which InputEnded also fires for -- ends it. This is the documented
	-- way to trigger a custom prompt, and it hands mouse players a click-to-pick-up that
	-- matches the click-to-yank mash. Keyboard and gamepad never touch this path.
	local HOLD_INPUTS = {
		[Enum.UserInputType.MouseButton1] = true,
		[Enum.UserInputType.Touch] = true,
	}
	ui.lockGui.hit.InputBegan:Connect(function(input)
		if HOLD_INPUTS[input.UserInputType] then
			ui.prompt:InputHoldBegin()
		end
	end)
	ui.lockGui.hit.InputEnded:Connect(function(input)
		if HOLD_INPUTS[input.UserInputType] then
			ui.prompt:InputHoldEnd()
		end
	end)

	-- MouseButton1Click, not Down/Up. Click fires for touch taps too, and unlike the
	-- Down/Up pair it needs no MouseLeave rescue, because there is no held state left to
	-- get stranded when a finger slides off a button mid-press.
	--
	-- The release button matters most. A phone has no Q key, so without it a touch
	-- player could commit to a haul and have no way to stop being rooted.
	ui.haulButton.MouseButton1Click:Connect(sendYank)
	ui.releaseButton.MouseButton1Click:Connect(sendRelease)

	-- Heartbeat, NOT RenderStepped. This used to matter because the ping audio ran
	-- here and could not be allowed to stall with the render loop; the ping is gone
	-- now, but the scope's sweep arm and blips are still driven off os.clock (not
	-- dt), so Heartbeat vs RenderStepped only changes how often they refresh, never
	-- what they show. Left on Heartbeat — moving it buys nothing.
	RunService.Heartbeat:Connect(function(dt)
		renderFrame(dt)
	end)

	renderState()
end

return Detector
