--[[
	DetectorController.lua — the lock-on prompt, the haul panel, and the unearth banner.

	WHAT THIS DRAWS NOW, AND WHAT IT USED TO DRAW.
	It used to be a NEEDLE, then a RADAR SCOPE — a corner dial with a ring for the
	detector radius and a blip per registered contact, drawn from a payload only this
	client receives (each player's ROLL for a signal is their own — DigService.rollFor —
	so signal X can be Rare for you and Common for the next player). Both are gone. The
	needle's "which direction" question is answered directly by the world now: every
	registerable signal stands up out of the ground as an aura, with FieldController's
	range ring around the player. The scope's per-player readout (rarity + "1 in N"
	odds, none of it clarity-gated any more — DigService.hintFor) moved onto the two
	places it is actually useful: the floating PICK UP card over the glow, and the haul
	panel's own title while you are pulling. The scope was removed on request as
	unnecessary once both of those carried the reading.

	The detector's per-player payload is still tracked below — state.radius,
	state.contacts and state.contactOrigin — because FieldController reads it for the
	ground ring and the per-player aura-well tint (Detector.radius / contactRarityAt).
	It just isn't drawn on the HUD.

	NO SOUND. The detector used to carry hot/cold by audio — a rate-and-pitch ping
	keyed to the nearest contact, plus a chirp on each new reveal (PLAN §10.7's
	"sweep with your eyes half shut"). Both were removed on request. The feedback is
	entirely in the world now: the aura wells and the range ring (FieldController).
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
local Tuning = require(Shared.Config.Tuning)
local Payload = require(Shared.Config.Payload)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local HaulRope = require(script.Parent.Parent.HaulRope)
local HaulSuccess = require(script.Parent.Parent.HaulSuccess)
local Sfx = require(script.Parent.Parent.Sfx)
local Dock = UIKit.Dock

local Detector = {}

-- Same fields UIKit.C already carries (panel/stroke/text/dim/green/amber/red/scope),
-- so every COLOR.xxx read throughout render/state logic below keeps working
-- unchanged — this is an alias, not a copy, on purpose.
local COLOR = UIKit.C

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

-- The HUGE / GIGA strip's box. Bottom-centred one band above the inventory's
-- Notice pill (which sits at Dock.VITALS_CLEAR and is 50 tall), wide enough that the
-- auto-sized strip inside never clips. CALLOUT_RISE is how far it slides on the way
-- in and on the way out.
local CALLOUT_HEIGHT = 50
local CALLOUT_WIDTH = 640
local CALLOUT_BOTTOM = Dock.VITALS_CLEAR + 50 + Dock.GAP
local CALLOUT_RISE = 26

-- The pick-up prompt's face. ProximityPrompt.Style is Custom (see build), so Roblox
-- draws nothing itself and these drive our own billboard: how far it floats over the
-- buried signal, and the two tweens it opens and closes with. A "Back" ease on the way
-- in gives the card a small overshoot so it reads as landing on the spot.
local LOCKGUI_RISE = 2.4 -- studs above the signal the card hovers at rest
local LOCKGUI_SHOW_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LOCKGUI_HIDE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- The keycap, which since the panel went away (buildLockPromptGui) IS the prompt: a
-- little larger than the 46px it was when it sat inset on a card, because it now has
-- to hold the whole thing on its own. The verb hangs under it.
--
-- KEY_TEXT_SIZE is the glyph size for a SINGLE character -- "E" or the gamepad's "X".
-- Touch has no key to show and gets the word HOLD instead, which needs its own much
-- smaller size to fit the same cap; both are swapped in on PromptShown (start()).
local KEYCAP_SIZE = 58
local KEYCAP_RADIUS = UDim.new(0, 17)
local KEY_TEXT_SIZE = 28
local KEY_TEXT_SIZE_TOUCH = 15
-- Set solid in the house font (UIKit.House, Gotham Black), on request: the old
-- hand-tracked "P I C K   U P" in Gotham Bold read airier but weaker than the rest of
-- the HUD. Black caps set solid read as one punchy word, so no tracking spaces now.
local ACTION_TEXT = "PICK UP"
local ACTION_TEXT_SIZE = 18

-- THE PROMPT WAITS FOR THE SPOT (on request: it landed on bare ground and sat there for
-- about half a second while the glow came up underneath it). It hangs directly over one
-- spot and nothing else, so its position alone says "this, here" — and it cannot say
-- that about ground with nothing on it yet.
--
-- It is not a fixed delay. It asks FieldController how far up the spot actually is and
-- goes the moment there is something to point at, which in practice is the same frame
-- you arrive: the reveal (client/SpotCracks, REVEAL) was cut to finish inside the walk
-- from the edge of the detector radius, so a spot is ~87% up by the time the starting
-- kit can stand on it. The wait only shows up in the cases where the spot genuinely IS
-- new under your feet — a signal that respawned where you are standing, a stage you
-- just walked into.
--
-- AND IT CAN ONLY EVER DELAY THE CARD, NEVER WITHHOLD IT. PROMPT_WAIT_CAP is the hard
-- stop: this is a cosmetic system gating a gameplay affordance, and if the cracks never
-- arrive at all (FieldController never tracked the aura, the rarity never resolved) the
-- player still gets their prompt a beat later. A pick-up you cannot trigger is a far
-- worse bug than a card over a dim spot.
local PROMPT_MIN_SHOWN = 0.6 -- how far up the spot has to be before the card is offered
local PROMPT_WAIT_CAP = 1.0 -- seconds the card will wait on a spot before showing regardless

local YANK_KICK_SECONDS = 0.12
-- No yank for this long and the soil is winning: the bar's strain judder gets harder.
local ROPE_IDLE_SECONDS = 0.2

-- ── The haul widget's interior ──────────────────────────────────────────────────
-- ALL DERIVED FROM Dock.HAULPANEL_SIZE and the vitals bars' own columns, never
-- re-hardcoded against them.
--
-- THERE IS NO PANEL BEHIND ANY OF THIS. The widget is a transparent container that
-- only exists to be shown and hidden as a unit; each piece carries itself.
--
-- SLIM ROWS, laid out like the vitals bars right under them (on request, 2026-10-09:
-- the taller panel covered the character). On top, a label row with the rarity word
-- (the metres readout was removed on request). Under it, the fuse's wick on its own
-- thin row, then the pull bar (HaulRope), in exactly the health bar's column -- same
-- left edge, same length -- with the magnet as a cell at its right end and the
-- progress as a solid rarity-colour fill with a percentage. LET GO is a red X badge in
-- the icon column, lined up with the radiation and heart badges below; REEL IN is the
-- bar itself (E on a keyboard, a tap anywhere on it on touch).
local PANEL_WIDTH = Dock.HAULPANEL_SIZE.X.Offset
local LABEL_HEIGHT = 24
local ROW_GAP = 3
local BAR_X = Dock.VITALS_BAR_X
-- The label row, then the wick's own row (HaulRope draws it over the bar), then the bar.
local BAR_Y = LABEL_HEIGHT + ROW_GAP + HaulRope.WICK_ROW
local BAR_WIDTH = PANEL_WIDTH - BAR_X
local BAR_HEIGHT = Dock.HAULPANEL_SIZE.Y.Offset - BAR_Y
local BADGE = Dock.VITALS_ICON -- the LET GO badge, the vitals badges' size
local TITLE_TEXT = 22 -- the rarity word
local TITLE_WIDTH = 220 -- clears "Legendary", the longest rarity in Rarity.ORDER
local WEAK_TEXT = 18 -- "Weak magnet!", right end of the label row
local WEAK_WIDTH = 160
local WEAK_PULSE = 6 -- radians per second of its breathing

-- How fast the bar's nuke chases the server's value (1/seconds). Smoothed rather
-- than snapped because drag is continuous and 10 Hz updates make a steady sink look
-- like a stutter; fast enough that a yank still lands as a visible jump.
local FILL_LERP_RATE = 14

-- The pull fuse (Config/Detonation) has no readout of its own any more (on request,
-- 2026-10-09: the seconds chip over the bar was removed). The wick over the bar is the
-- time left; once it ARMS, the bar's outline flashes red at this rate (rad/sec) --
-- together with LET GO greying out, that is how you know the release has stopped.
local FUSE_ARMED_PULSE = 7

-- THE SUCCESS MOMENT (HaulSuccess), off the Unearthed remote: for this long the bar
-- stays up, snapped to 100%, with its outline flashing gold; then it is gone and
-- "Success!" with its rays plays in its spot.
local SUCCESS_FLASH = 0.25

type Contact = { dx: number, dz: number, rarity: string?, scale: number? }

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
	inRange = false,
	blocked = nil :: string?,
	-- Stages the soil outclasses the held magnet (0 = rated for it). Server-sent, read
	-- only to crack the soil round the nuke on the haul rope as the over-tier grind
	-- steepens -- it never
	-- blocks a haul and never becomes a status message.
	overGrip = 0,
	digProgress = 0,
	-- The locked signal's burial depth in studs (server-sent only while locked), and
	-- the stage it is in: the haul readout counts the metres off it, and the rope's dirt end wears that
	-- stage's soil.
	depth = nil :: number?,
	stageId = nil :: number?,
	-- Committed to a signal and rooted in place. The server is the authority on this;
	-- the client never decides it is locked on its own, because being locked is what
	-- takes the player's movement away.
	locked = false,
	-- The locked nuke's pull fuse (Config/Detonation), server-sent only while locked:
	-- 0..1 through its window, whether it has armed, the seconds left to detonation
	-- and the window itself. `fuseAt` is the os.clock the payload landed, so the
	-- seconds count down smoothly between ticks (renderFrame).
	fuse = nil :: number?,
	fuseArmed = false,
	fuseLeft = nil :: number?,
	fuseWindow = nil :: number?,
	fuseAt = 0,
	-- The new-player tutorial's first dig lights no fuse (Config/Tutorial.isSafeDig);
	-- the readout says so instead of counting down a window of 0.
	fuseless = false,
}

local ui = {}
-- What the fill is currently DRAWING, chasing state.digProgress. Separate from the
-- server's value so smoothing never feeds back into what we think progress is.
local shownProgress = 0
-- Same, for the fuse bar chasing state.fuse.
local shownFuse = 0

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
-- os.clock() of the last Unearthed (a haul landed), while its success moment plays.
local successAt: number? = nil

-- The spot the pick-up card is currently waiting on, and when that wait started (see
-- PROMPT_MIN_SHOWN). Cleared by nothing: a new nearest core replaces both.
local promptWaitCore: BasePart? = nil
local promptWaitSince = 0

-- Sibling controller, required lazily in start() for the same reason it requires us
-- that way -- the two point at each other and load order must not decide which wins.
local FieldController = nil

-- ── Build ───────────────────────────────────────────────────────────

--- The pick-up prompt's whole face. The ProximityPrompt is Style = Custom, which means
--- Roblox renders NOTHING for it -- this billboard is the entire visual, wired to the
--- prompt through ProximityPromptService's Shown/Hidden/Hold events in start().
---
--- THERE IS NO PANEL ANY MORE. This used to be a 190x76 card: a glass panel with a
--- rounded rectangle, a 45deg pin planting it on the spot, a keycap inset on the left
--- and "PICK UP" set beside it. It was replaced on request with something simpler and
--- cleaner -- the KEY ITSELF, with the verb under it, and nothing else. What went:
---   * the panel, its gradient and its stroke. The panel was already near-transparent
---     glass so the item breaking the surface showed through it; deleting it outright
---     is the same intent taken to its end, and the breathing stroke that carried the
---     card's pulse simply moved onto the keycap's own outline (renderFrame).
---   * the pin. It said "this, here" with a downward arrow, which a prompt that hovers
---     directly over the spot and nothing else already says by position alone.
--- The result is roughly a third of the footprint over a signal you are stood on, and
--- the world is no longer read through a sheet of tinted glass.
---
--- Custom style also drops the built-in mobile button and the gamepad glyph, so two
--- things here stand in for them: the whole billboard is a TextButton that drives
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
	-- Offset (pixels), not scale (studs), so the prompt holds a constant on-screen size
	-- for the whole 5-stud window it is up rather than ballooning as you close in. The
	-- 150x88 is in DESIGN pixels: UIKit.billboardCanvas, below, scales it with the rest
	-- of the HUD so it does not shrink beside the HUD on a big screen. Taller and much
	-- narrower than the old 190x76 card, because the layout turned from a row (keycap
	-- beside text) into a column (keycap over text) -- and the height is exactly the
	-- column: KEYCAP_SIZE, an 8px gap, and the 22px the verb's line box takes.
	root.StudsOffsetWorldSpace = Vector3.new(0, LOCKGUI_RISE, 0)
	root.AlwaysOnTop = true -- the signal is buried; the cue has to punch through the soil
	-- NO MaxDistance cap. It is measured CAMERA-to-adornee, not character-to-adornee, and
	-- a third-person camera sits 12-15+ studs behind the player (further if they zoom
	-- out) -- a cap near DIG_RADIUS hid the card outright while the player stood on the
	-- spot. Whether the card should show at all is already decided by the prompt's own
	-- MaxActivationDistance and updateLockPrompt's enable gate; this just has to draw.
	root.LightInfluence = 0
	root.Enabled = false
	-- PARENTED TO PlayerGui, NOT THE ADORNEE. A BillboardGui under Workspace draws fine
	-- but its buttons never receive input, so `hit` below was dead: on a phone, where it
	-- is the ONLY way to press a Custom prompt, the HOLD keycap did nothing at all. The
	-- Adornee still pins it to the spot; Active lets the press sink here instead of
	-- also swinging the camera. Directly under PlayerGui is also what lets
	-- WashController's hideHud put it away with the rest of the HUD.
	root.Active = true
	root.ResetOnSpawn = false
	root.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local canvas = UIKit.billboardCanvas(root, Vector2.new(150, KEYCAP_SIZE + 8 + 22))

	-- Everything visible lives under `card` so one UIScale bounces the lot; `hit` sits
	-- outside it so the tap target never moves or scales with the animation.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundTransparency = 1
	card.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = card

	-- Keycap. The whole prompt now, and the hold timer with it: it fills bottom-up in
	-- the signal's colour across the hold, the same reading the haul panel's bar gives
	-- the mash. Centred on the billboard's top, with the verb hung underneath.
	local keycap = Instance.new("Frame")
	keycap.Name = "Keycap"
	keycap.AnchorPoint = Vector2.new(0.5, 0)
	keycap.Position = UDim2.fromScale(0.5, 0)
	keycap.Size = UDim2.fromOffset(KEYCAP_SIZE, KEYCAP_SIZE)
	keycap.BackgroundColor3 = COLOR.panel
	keycap.BackgroundTransparency = 1
	keycap.BorderSizePixel = 0
	keycap.ClipsDescendants = true
	keycap.ZIndex = 2
	keycap.Parent = card

	local keycapCorner = Instance.new("UICorner")
	keycapCorner.CornerRadius = KEYCAP_RADIUS
	keycapCorner.Parent = keycap

	-- THE ONLY STROKE LEFT, and it inherited the panel stroke's job: renderFrame
	-- breathes it on the aura's own pulse period once the show tween has settled, so
	-- the key and FieldController's ground ring beat together.
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.Color = COLOR.scope
	stroke.Thickness = 2.5
	stroke.Transparency = 1
	stroke.Parent = keycap

	local keycapFill = Instance.new("Frame")
	keycapFill.Name = "Fill"
	keycapFill.AnchorPoint = Vector2.new(0.5, 1)
	keycapFill.Position = UDim2.fromScale(0.5, 1)
	keycapFill.Size = UDim2.fromScale(1, 0)
	keycapFill.BackgroundTransparency = 1
	keycapFill.BorderSizePixel = 0
	keycapFill.ClipsDescendants = true
	keycapFill.ZIndex = 2
	keycapFill.Parent = keycap

	-- The colour itself. ClipsDescendants ignores UICorner, so a bare square fill poked
	-- its corners out past the keycap's rounded outline. Instead `keycapFill` is only the
	-- rising (rectangular) clip -- its flat top edge is the liquid level -- and this
	-- key-sized rounded slab sits pinned to its bottom, so the fill takes the keycap's
	-- own corners at every height.
	local keycapLiquid = Instance.new("Frame")
	keycapLiquid.Name = "Liquid"
	keycapLiquid.AnchorPoint = Vector2.new(0.5, 1)
	keycapLiquid.Position = UDim2.fromScale(0.5, 1)
	keycapLiquid.Size = UDim2.fromOffset(KEYCAP_SIZE, KEYCAP_SIZE)
	keycapLiquid.BackgroundColor3 = COLOR.scope
	keycapLiquid.BackgroundTransparency = 1
	keycapLiquid.BorderSizePixel = 0
	keycapLiquid.ZIndex = 2
	keycapLiquid.Parent = keycapFill

	local keycapLiquidCorner = Instance.new("UICorner")
	keycapLiquidCorner.CornerRadius = KEYCAP_RADIUS
	keycapLiquidCorner.Parent = keycapLiquid

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = UIKit.Font.hero -- Gotham Black, the house font
	keyLabel.Text = "E"
	keyLabel.TextSize = KEY_TEXT_SIZE
	keyLabel.TextColor3 = COLOR.text
	keyLabel.TextTransparency = 1
	keyLabel.TextStrokeTransparency = 1
	keyLabel.ZIndex = 3
	keyLabel.Parent = keycap

	-- The glyph gets UIKit's black outline by hand (it is not a UIKit.label -- it has
	-- to be a plain child of the clipping keycap). NOT decoration: the fill climbing
	-- behind it is the signal's colour, and at full hold a white E sat on Legendary
	-- amber or an Anomaly's white was the one moment the key stopped reading. The
	-- outline makes the glyph independent of whatever colour arrives under it.
	--
	-- Thickness is re-derived whenever the glyph is swapped (setKeyGlyph), because the
	-- two sizes are far enough apart that one thickness cannot serve both: heavy enough
	-- for a 26px "E" turns a 15px "HOLD" into a black blob.
	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = COLOR.outline
	keyStroke.Thickness = UIKit.strokeThicknessFor(KEY_TEXT_SIZE)
	keyStroke.LineJoinMode = Enum.LineJoinMode.Round
	keyStroke.Transparency = 1
	keyStroke.Parent = keyLabel

	-- The verb, centred under the key. It carries the signal's colour (see
	-- updateLockPrompt) and UIKit's heavy black outline, which is the whole reason it
	-- holds against bright ground now there is no panel behind it. Gotham Black set
	-- solid (see ACTION_TEXT).
	local action = UIKit.label(card, {
		name = "Action",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.fromScale(0.5, 1),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.hero,
		textSize = ACTION_TEXT_SIZE,
		color = COLOR.scope,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
	})
	action.Text = ACTION_TEXT
	action.TextTransparency = 1

	-- UIKit.label hangs a black outline stroke on the label. It does not fade with
	-- TextTransparency, so it has to be fetched and driven explicitly -- without this
	-- the prompt hides and leaves a black ghost of the word hanging over the spot.
	local actionStroke = action:FindFirstChildOfClass("UIStroke")

	-- The billboard is the touch (and mouse) target; see the header. Transparent,
	-- full-bleed, on top, and OUTSIDE `card` so the bounce never shifts it. It stays the
	-- size of the whole billboard even though the visible prompt no longer fills it --
	-- a lone keycap is a small target on a phone, and the slack around it is deliberate.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit:SetAttribute("NoClickSound", true) -- a hold, not a click (SfxController)
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = 5
	hit.Parent = canvas

	-- (instance, property, value-when-shown) -- revealLockGui tweens each of these to
	-- its shown value on the way in and to 1 on the way out.
	--
	-- WHAT CARRIES THE PROMPT IS THE OUTLINE AND THE TEXT, not a fill. That was true of
	-- the old glass card and it is more true now there is no panel at all: the keycap's
	-- own background still rests part-transparent so the ground shows through it, and if
	-- the stroke and the text layers ever stopped landing at 0 the whole thing would
	-- dissolve into the soil.
	local fades = {
		{ keycap, "BackgroundTransparency", 0.34 },
		{ stroke, "Transparency", 0.05 },
		{ keycapLiquid, "BackgroundTransparency", 0.2 },
		{ keyLabel, "TextTransparency", 0 },
		{ keyStroke, "Transparency", 0 },
		{ action, "TextTransparency", 0 },
	}
	if actionStroke then
		table.insert(fades, { actionStroke, "Transparency", 0 })
	end

	return {
		root = root,
		card = card,
		scale = scale,
		keycap = keycap,
		stroke = stroke,
		keycapFill = keycapFill,
		keycapLiquid = keycapLiquid,
		keyLabel = keyLabel,
		keyStroke = keyStroke,
		action = action,
		hit = hit,
		fades = fades,
	}
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DetectorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- NO RADAR SCOPE ANY MORE. A sweep dial sat in the bottom-right corner with a blip
	-- per registered contact, a radius ring and a rotating arm. It was removed on
	-- request as unnecessary: the per-player readout it used to justify itself with
	-- (rarity + "1 in N" odds) now lives on the floating pick-up card and the haul
	-- panel's own title, the world already answers "which direction" with the aura
	-- wells and FieldController's ground ring, and the "N stud sweep" radius readout
	-- was never load-bearing. The detector's per-player payload (state.radius /
	-- state.contacts / state.contactOrigin) is still tracked below — FieldController
	-- reads it for the ground ring and the per-player well tint — it just isn't drawn
	-- on the HUD.

	-- Everything on screen goes on the scaled canvas (UIKit.canvas). The pick-up card is
	-- a BillboardGui and scales itself — see buildLockPromptGui.
	local canvas = UIKit.canvas(gui)

	-- Status line: dead centre, above the instrument band.
	ui.status = UIKit.label(canvas, {
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
	local banner, bannerStroke = UIKit.panel(canvas, {
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

	-- The oversized-payload callout: a low strip just above the hotbar (one band over
	-- the inventory's Notice pill, so a "bag full" on the same dig never lands on it).
	-- Black with faded ends, the tier word in its colour and "×2.4 value" in white,
	-- both outlined like the rest of the HUD. It slides up into place and up out of
	-- it; a CanvasGroup carries the fade, because a UIStroke ignores TextTransparency.
	local callout = Instance.new("CanvasGroup")
	callout.Name = "PayloadCallout"
	callout.AnchorPoint = Vector2.new(0.5, 1)
	callout.Position = UDim2.new(0.5, 0, 1, -CALLOUT_BOTTOM)
	callout.Size = UDim2.fromOffset(CALLOUT_WIDTH, CALLOUT_HEIGHT)
	callout.BackgroundTransparency = 1
	callout.GroupTransparency = 1
	callout.Visible = false
	callout.Parent = canvas

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Position = UDim2.fromScale(0.5, 0.5)
	strip.Size = UDim2.fromScale(0, 1)
	strip.AutomaticSize = Enum.AutomaticSize.X
	strip.BackgroundColor3 = Color3.new(0, 0, 0)
	strip.BackgroundTransparency = 0
	strip.BorderSizePixel = 0
	strip.Parent = callout
	-- Solid through the middle, gone at both ends: a band, not a box.
	local stripFade = Instance.new("UIGradient")
	stripFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.35),
		NumberSequenceKeypoint.new(0.82, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	stripFade.Parent = strip
	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingLeft = UDim.new(0, 46)
	stripPad.PaddingRight = UDim.new(0, 46)
	stripPad.Parent = strip
	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stripLayout.Padding = UDim.new(0, 10)
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Parent = strip

	local function stripText(name: string, order: number, font: Enum.Font, outline: number): (TextLabel, UIStroke)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0, 1)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Font = font
		label.Parent = strip
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = outline
		stroke.Parent = label
		return label, stroke
	end
	local calloutWord, calloutWordStroke = stripText("Word", 1, Enum.Font.GothamBlack, 3)
	local calloutMult = stripText("Mult", 2, Enum.Font.GothamBold, 2)
	calloutMult.TextColor3 = Color3.new(1, 1, 1)

	ui.callout = callout
	ui.calloutWord = calloutWord
	ui.calloutWordStroke = calloutWordStroke
	ui.calloutMult = calloutMult

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
	-- fill, no corner, no stroke -- it exists only to place the rope and its readout as
	-- a unit and to be shown and hidden in one line.
	local haul = Instance.new("Frame")
	haul.Name = "HaulPanel"
	haul.Size = Dock.HAULPANEL_SIZE
	haul.AnchorPoint = Vector2.new(0.5, 1)
	haul.BackgroundTransparency = 1
	haul.BorderSizePixel = 0
	haul.Visible = false
	haul.Parent = canvas
	ui.haul = haul

	-- CENTRED ON THE VITALS BARS, ONE GAP ABOVE THEM, AND JUST AS WIDE (on request,
	-- 2026-10-09). It used to sit just right of centre to keep off the nuke climbing out
	-- of the soil; the user wanted it docked over the hotbar cluster instead, edge to
	-- edge with the health / rads bars (Dock.VITALS_WIDTH is also HAULPANEL_SIZE.X).
	-- Re-placed on every canvas resize, because the design width moves with both the
	-- window and the HUD scale.
	--
	-- SHRUNK TO FIT. Its own UIScale is the smaller of two fits: the HEIGHT one keeps its
	-- top clear of the corner row on a short landscape phone (Dock.HAULPANEL_TOP_CLEAR),
	-- and the WIDTH one follows the vitals bars, which HudController narrows on a screen
	-- that cannot fit 640 between the side margins it and the hotbar keep. A UIScale
	-- keeps the Position, and the AnchorPoint is the bottom centre, so it shrinks down
	-- toward the bars, never off them.
	-- The "Success!" moment's own layer, placed and scaled exactly like the panel so
	-- the word lands in the bar's spot (renderFrame plays it; the panel is hidden then).
	ui.success = HaulSuccess.build(canvas, Dock.HAULPANEL_SIZE, Vector2.new(BAR_X + BAR_WIDTH / 2, BAR_Y + BAR_HEIGHT / 2))
	local successFit = Instance.new("UIScale")
	successFit.Parent = ui.success.root

	local haulFit = Instance.new("UIScale")
	haulFit.Parent = haul
	local function placeHaul()
		local s = UIKit.canvasScale(canvas)
		local width = canvas.AbsoluteSize.X / s
		local height = canvas.AbsoluteSize.Y / s
		local room = height - Dock.HAULPANEL_BOTTOM - Dock.HAULPANEL_TOP_CLEAR
		local margin = math.max(Dock.ROW_SIDE_MARGIN, UIKit.touchCorner().X + Dock.GAP)
		local barsWidth = math.clamp(width - 2 * margin, 240, Dock.VITALS_WIDTH)
		local fit = math.min(
			math.clamp(room / Dock.HAULPANEL_SIZE.Y.Offset, Dock.HAULPANEL_MIN_FIT, 1),
			barsWidth / Dock.HAULPANEL_SIZE.X.Offset
		)
		haulFit.Scale = fit
		haul.Position = UDim2.new(0.5, 0, 1, -Dock.HAULPANEL_BOTTOM)
		successFit.Scale = fit
		ui.success.root.Position = haul.Position
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeHaul)
	-- The canvas's AbsoluteSize does NOT move when the HUD scale does (its Size is
	-- 1/scale, then the UIScale multiplies it back), so a scale that settles after this
	-- was built left the panel placed off the old design width -- off the right edge on
	-- the first haul. Re-place on the scale too, and again whenever it is shown.
	local scaler = canvas:FindFirstChildOfClass("UIScale")
	if scaler then
		scaler:GetPropertyChangedSignal("Scale"):Connect(placeHaul)
	end
	ui.placeHaul = placeHaul
	placeHaul()

	-- THE PULL BAR: the picture of the haul, in the health bar's column. The nuke slides
	-- along it from the dirt into the magnet cell, so how far along it is IS the
	-- progress, and the fuse burns down the wick on its top edge (HaulRope's header).
	-- renderState paints its dirt end in the stage's soil and the nuke in the signal's
	-- colour; renderFrame moves both every frame.
	ui.rope = HaulRope.build(haul, UDim2.fromOffset(BAR_X, BAR_Y), BAR_WIDTH, BAR_HEIGHT)
	HaulRope.showKeycap(ui.rope, UserInputService.KeyboardEnabled)

	-- REEL IN IS THE BAR. A clear button laid over the whole of it, because a phone has
	-- no E key -- without something tappable here the entire second beat would be
	-- keyboard-only. Named HaulButton: the tutorial's pointer finds it by that name.
	local haulButton = Instance.new("TextButton")
	haulButton.Name = "HaulButton"
	haulButton.Position = UDim2.fromOffset(BAR_X, BAR_Y)
	haulButton.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	haulButton.BackgroundTransparency = 1
	haulButton.Text = ""
	haulButton.ZIndex = 30
	haulButton.Parent = haul
	ui.haulButton = haulButton
	-- Mashed: the shovel crunch is its sound, a UI click on top would be noise.
	haulButton:SetAttribute("NoClickSound", true)

	-- LET GO, IN THE ICON COLUMN. Locking roots the character, so a player who cannot
	-- find the way out is stuck standing in a field: a real button, not only a key hint,
	-- because on touch there is no Q. A red badge the size of the radiation and heart
	-- badges under it, at the far (dirt) end from the magnet -- hitting the wrong one ends
	-- the haul. Q on a keyboard, an X on touch; greyed with no letter once the fuse arms.
	local releaseButton = Instance.new("TextButton")
	releaseButton.Name = "ReleaseButton"
	releaseButton.Position = UDim2.fromOffset(0, BAR_Y + (BAR_HEIGHT - BADGE) / 2)
	releaseButton.Size = UDim2.fromOffset(BADGE, BADGE)
	releaseButton.BackgroundColor3 = COLOR.red
	releaseButton.BorderSizePixel = 0
	releaseButton.AutoButtonColor = true
	releaseButton.Text = ""
	releaseButton.ZIndex = 30
	releaseButton.Parent = haul
	local releaseCorner = Instance.new("UICorner")
	releaseCorner.CornerRadius = UDim.new(0.5, 0)
	releaseCorner.Parent = releaseButton
	local releaseStroke = Instance.new("UIStroke")
	releaseStroke.Color = COLOR.outline
	releaseStroke.Thickness = 2
	releaseStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	releaseStroke.Parent = releaseButton
	ui.releaseButton = releaseButton
	-- THE MARK: a white X drawn from two crossed bars (on request, 2026-10-09: the "Q"
	-- letter read as a key hint, not a button). The Q key still lets go.
	local cross = Instance.new("Frame")
	cross.Name = "Cross"
	cross.Size = UDim2.fromScale(1, 1)
	cross.BackgroundTransparency = 1
	cross.ZIndex = 31
	cross.Parent = releaseButton
	for _, angle in { 45, -45 } do
		local stroke = Instance.new("Frame")
		stroke.AnchorPoint = Vector2.new(0.5, 0.5)
		stroke.Position = UDim2.fromScale(0.5, 0.5)
		stroke.Size = UDim2.fromOffset(math.round(BADGE * 0.56), 4)
		stroke.Rotation = angle
		stroke.BackgroundColor3 = COLOR.text
		stroke.BorderSizePixel = 0
		stroke.ZIndex = 31
		stroke.Parent = cross
		local edge = Instance.new("UIStroke")
		edge.Color = COLOR.outline
		edge.Thickness = 1
		edge.Parent = stroke
	end
	ui.releaseCross = cross

	-- THE LABEL ROW, over the bar: what the detector reads about the thing you locked
	-- onto, the fuse, and how far it still has to come. The rarity word carries the
	-- accent tint (in step with the nuke's band); no "1 in N" odds (on request): with the
	-- rarity word beside it, the odds named the exact nuke coming up. All of it lands on
	-- any detector (DigService.hintFor is not clarity-gated), and all of it takes the
	-- kit's hard outline, because with no panel behind it this text can end up over
	-- sunlit sludge.
	ui.haulTitle = UIKit.label(haul, {
		name = "Title",
		position = UDim2.fromOffset(BAR_X, 0),
		size = UDim2.fromOffset(TITLE_WIDTH, LABEL_HEIGHT),
		font = UIKit.Font.title,
		textSize = TITLE_TEXT,
		color = COLOR.scope,
		xAlign = Enum.TextXAlignment.Left,
	})

	-- A question mark, IN THE RARITY WORD'S OWN SLOT. You committed to a lump in the
	-- dirt; whether you get to know what it is is the detector's job, not this widget's.
	-- Hidden the moment the rarity resolves -- the two share one rectangle, and
	-- "LEGENDARY" next to a "?" reads as a bug.
	ui.haulQuestion = UIKit.label(haul, {
		name = "HaulQuestion",
		position = UDim2.fromOffset(BAR_X, 0),
		size = UDim2.fromOffset(TITLE_WIDTH, LABEL_HEIGHT),
		font = UIKit.Font.title,
		textSize = TITLE_TEXT,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Left,
		text = "?",
	})

	-- "Weak magnet!", AT THE ROW'S RIGHT END (on request, 2026-10-09: mockup 1). Shown
	-- only while the soil round this nuke outclasses the magnet (state.overGrip > 0), in
	-- red with a slow pulse, so the cracks and judder on the bar finally come with words.
	ui.haulWeak = UIKit.label(haul, {
		name = "WeakMagnet",
		position = UDim2.fromOffset(PANEL_WIDTH, LABEL_HEIGHT / 2),
		anchorPoint = Vector2.new(1, 0.5),
		size = UDim2.fromOffset(WEAK_WIDTH, LABEL_HEIGHT),
		font = UIKit.Font.title,
		textSize = WEAK_TEXT,
		color = COLOR.red,
		xAlign = Enum.TextXAlignment.Right,
		text = "Weak magnet!",
		visible = false,
	})
	ui.haulWeakPulse = Instance.new("UIScale")
	ui.haulWeakPulse.Parent = ui.haulWeak

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

local function renderFrame(dt: number)
	-- Chase rather than snap. Exponential so it converges at the same visual rate
	-- whatever the framerate -- the naive `+= (target - shown) * rate * dt` overshoots
	-- and oscillates the moment dt gets large, which on a nuke the player is staring at
	-- while mashing is very visible.
	shownProgress += (state.digProgress - shownProgress) * (1 - math.exp(-FILL_LERP_RATE * dt))

	-- The kick: one ease-out press per yank, driven off the local timestamp so it starts
	-- on the same frame the key went down, on REEL IN and as a jolt on the nuke -- where
	-- the player's finger and eyes are during a haul. Still reports the INPUT, never the
	-- outcome -- it confirms a click happened, it does not promise the server honoured it.
	local sinceYank = os.clock() - lastYankAt
	local kick = if sinceYank < YANK_KICK_SECONDS then (1 - sinceYank / YANK_KICK_SECONDS) ^ 2 else 0

	if successAt and not state.locked then
		-- THE SUCCESS MOMENT. A beat of the full bar flashing gold, then "Success!" with
		-- its rays in the bar's spot (HaulSuccess), then nothing.
		local since = os.clock() - successAt
		if since < SUCCESS_FLASH then
			ui.haul.Visible = true
			ui.haulWeak.Visible = false
			HaulRope.step(ui.rope, {
				progress = 1,
				strain = 0,
				kick = 0,
				idle = false,
				now = os.clock(),
				fuse = nil,
				alarm = 0,
				glow = math.sin(since / SUCCESS_FLASH * math.pi),
			})
			HaulSuccess.draw(ui.success, nil)
		else
			ui.haul.Visible = false
			local t = since - SUCCESS_FLASH
			HaulSuccess.draw(ui.success, t)
			if t >= HaulSuccess.DURATION then
				successAt = nil
			end
		end
	elseif state.locked then
		HaulSuccess.draw(ui.success, nil)
	end

	if state.locked then
		-- THE NUKE IS THE BAR. Every haul starts it at the rope's dirt end and it slides
		-- the full length on progress alone; the depth only sets the metres still to come
		-- up, printed over the magnet end.
		local climbed = math.clamp(shownProgress, 0, 1)

		-- THE FUSE. The wick chases the server like the nuke does; the white tick on it is
		-- the arm line. Armed, the bar's outline flashes red: there is one way out now.
		local fuse = state.fuse or 0
		shownFuse += (fuse - shownFuse) * (1 - math.exp(-FILL_LERP_RATE * dt))
		local fill = math.clamp(shownFuse, 0, 1)
		local alarm = if state.fuseArmed then 0.5 + 0.5 * math.sin(os.clock() * FUSE_ARMED_PULSE) else 0

		-- The soil outclasses the magnet: say so, breathing, at the label row's right end.
		local weak = state.overGrip > 0
		ui.haulWeak.Visible = weak
		if weak then
			ui.haulWeakPulse.Scale = 1 + 0.06 * math.sin(os.clock() * WEAK_PULSE)
		end

		HaulRope.step(ui.rope, {
			progress = climbed,
			strain = state.overGrip,
			kick = kick,
			idle = sinceYank > ROPE_IDLE_SECONDS and climbed > 0,
			now = os.clock(),
			fuse = if state.fuseless then nil else fill,
			alarm = alarm,
		})
	end

	-- The pick-up prompt's idle life: a slow hover, and the keycap outline breathing on
	-- the aura's OWN pulse period so the key and FieldController's ground ring beat
	-- together. That breath used to live on the panel stroke; with the panel gone
	-- (buildLockPromptGui) the keycap's outline is the only stroke left and inherited
	-- it. Only once the show tween has settled -- before that revealLockGui owns both
	-- the offset and the stroke.
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

--- What the keycap says, and how big. Custom prompt style drops Roblox's own gamepad
--- glyph and touch button, so the cap has to name this player's input itself. The
--- outline thickness is re-derived here rather than fixed at build time because touch's
--- "HOLD" is a whole word at 15px while "E"/"X" are single glyphs at 28 — one thickness
--- cannot flatter both (see the stroke in buildLockPromptGui).
local function setKeyGlyph(text: string, textSize: number)
	local g = ui.lockGui
	g.keyLabel.Text = text
	g.keyLabel.TextSize = textSize
	g.keyStroke.Thickness = UIKit.strokeThicknessFor(textSize)
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

	-- Is there a spot under the card yet? See PROMPT_MIN_SHOWN. Timed from the first
	-- tick THIS core was the nearest one, so walking from one spot straight onto another
	-- restarts the wait rather than inheriting the last one's.
	if best ~= promptWaitCore then
		promptWaitCore, promptWaitSince = best, os.clock()
	end
	-- Defaults to "fully up" if the sibling is somehow not loaded, so a missing
	-- FieldController can never be the reason a player cannot pick something up.
	local spot = if FieldController then FieldController.spotShown(best) else 1
	if spot < PROMPT_MIN_SHOWN and os.clock() - promptWaitSince < PROMPT_WAIT_CAP then
		ui.prompt.Enabled = false
		return
	end

	ui.promptHolder.Position = best.Position

	-- The prompt carries no rarity text any more, but the accent still does: the rarity
	-- colour on the keycap's outline, its hold fill and the verb (any detector reads it
	-- now), scope blue only in the frame before it resolves. Cheap, and the hint can
	-- change under the prompt, so set it every tick.
	local accent = signalColor()
	ui.prompt.ObjectText = if state.rarityHint then string.upper(state.rarityHint)
		else "Buried Signal"
	ui.lockGui.action.TextColor3 = accent
	ui.lockGui.stroke.Color = accent
	ui.lockGui.keycapLiquid.BackgroundColor3 = accent

	ui.prompt.Enabled = true
end

local function renderState()
	updateLockPrompt()

	-- THE PANEL IS DRIVEN OFF THE SERVER'S `locked`, NOT off anything the client
	-- decided. Every release path lives on the server (bag full, signal gone, blackout,
	-- item surfaced), so the panel closing is always downstream of the lock actually
	-- being dropped -- it can never linger over a lock the server has already let go
	-- of, and it can never hide one that is still holding the player's feet.
	if state.locked and not ui.haul.Visible then
		ui.placeHaul()
	end
	-- Held up past the lock for the success flash (renderFrame).
	ui.haul.Visible = state.locked or (successAt ~= nil and os.clock() - successAt < SUCCESS_FLASH)
	if not state.locked then
		-- So the next lock's bar grows from empty rather than draining from this one's.
		shownFuse = 0
	end
	-- ARMED IS THE ONE STATE THE RELEASE DOES NOTHING IN (DigService's lock handler), so
	-- the button stops offering it rather than silently failing. It still sends if
	-- pressed -- the server is the judge, and the client must never be the reason a
	-- release did not go through.
	ui.releaseCross.Visible = not state.fuseArmed
	ui.releaseButton.BackgroundColor3 = if state.fuseArmed then COLOR.panel else COLOR.red
	if state.locked then
		-- THE SIGNAL'S COLOUR, in two places that move together: the band and glow on
		-- the nuke, and the wash it trails along the bar. Scope blue only in the brief
		-- frame before the rarity resolves -- the "?" over the rope is that state at
		-- rest; this is it in colour. The rope's dirt end is the stage's own soil (a
		-- no-op once set, so safe on every tick).
		local accent = signalColor()
		HaulRope.setAccent(ui.rope, accent)
		if state.stageId then
			HaulRope.paint(ui.rope, state.stageId)
		end
		-- The readout spells out what the colour only implies: the rarity word
		-- (state.rarityHint), on any detector -- exactly what DigService.hintFor sent.
		-- No "1 in N" under it (on request): rarity + odds pinned down the exact nuke.
		if state.rarityHint then
			ui.haulTitle.Text = state.rarityHint
		else
			ui.haulTitle.Text = ""
		end
		ui.haulTitle.TextColor3 = accent
		ui.haulQuestion.Visible = not state.rarityHint
		-- An under-rated magnet still locks on and still pulls. The rope shows it (the
		-- soil around the nuke cracks and glows, the nuke judders, harder the further the
		-- soil outclasses the magnet) and renderFrame adds "Weak magnet!" to the label
		-- row while state.overGrip > 0.
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
		ui.status.Text = ""
		return
	end

	if not state.hasSignal then
		-- Standing in a glow that somebody else's detector put there. This is a real
		-- state, not an error: auras are public, the depth gate is not.
		if state.blocked == "unregistered" then
			ui.status.Text = "that signal is buried too deep for your detector"
			ui.status.TextColor3 = COLOR.red
			return
		end

		-- Detector on, nothing revealed in range. The aura wells on the ground and
		-- FieldController's range ring are the only cue now; no status line for it.
		ui.status.Text = ""
		return
	end

	if state.blocked == "full" then
		ui.status.Text = "bag is full — sell at trader or store in locker"
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

--- "5 kg" / "12 kg" / "470 kg" — two sig figs under a kilo, whole numbers above.
--- Small dup of IndexController.formatWeight (the 2nd caller); lift to UIKit on a 3rd.
local function formatWeight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

--- THE REVEAL BANNER. Fired only straight out of the ground for a sealed find with no
--- crust to wash (onUnearthed below). The wash bay stages its own reveal, a blind sale
--- shows none, and a crusted dig no longer raises it with a "???".
local function showFind(found)
	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else COLOR.text

	local qualities = Rarity.qualities(found.modifier, found.bonus)
	local modifier = if #qualities == 0 then "" else table.concat(qualities, " ") .. " "
	local heft = if type(found.weight) == "number" then `  \u{00B7}  {formatWeight(found.weight)}` else ""
	ui.bannerRarity.Text = string.upper(modifier .. found.rarity) .. heft
	ui.bannerRarity.TextColor3 = colour
	ui.bannerName.Text = found.name
	ui.bannerFlavor.Text = found.flavor or ""
	ui.bannerStroke.Color = colour
	ui.callout.Visible = false
	ui.banner.Visible = true

	bannerToken += 1
	local token = bannerToken
	task.delay(3.5, function()
		if token == bannerToken then
			ui.banner.Visible = false
		end
	end)
end

--- A "HUGE ×1.8 value" / "GIGA ×2.4 value" strip just above the hotbar when a
--- dig rolled a big payload (Config/Payload.CALLOUTS). Slides up and fades in, holds,
--- then slides on up and fades out -- low and small so it never covers the field.
local CALLOUT_COLOR = {
	GIGA = Color3.fromHex("FACC15"),
	HUGE = COLOR.amber,
}

local function showCallout(label: string, mult: number)
	ui.banner.Visible = false
	bannerToken += 1 -- a pending banner hide must not outlive this
	local token = bannerToken

	-- GIGA is the rarer shout: bigger text, a thicker outline, and a longer hold.
	local giga = label == "GIGA"
	ui.calloutWord.Text = label
	ui.calloutWord.TextColor3 = CALLOUT_COLOR[label] or COLOR.amber
	ui.calloutWord.TextSize = if giga then 30 else 25
	ui.calloutWordStroke.Thickness = if giga then 3.5 else 3
	ui.calloutMult.Text = string.format("\u{00D7}%.1f value", mult)
	ui.calloutMult.TextSize = if giga then 19 else 17

	local rest = UDim2.new(0.5, 0, 1, -CALLOUT_BOTTOM)
	ui.callout.Position = rest + UDim2.fromOffset(0, CALLOUT_RISE)
	ui.callout.GroupTransparency = 1
	ui.callout.Visible = true
	TweenService:Create(ui.callout, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = rest,
		GroupTransparency = 0,
	}):Play()

	task.delay(if giga then 2.6 else 1.9, function()
		if token ~= bannerToken then
			return
		end
		local out = TweenService:Create(ui.callout, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = rest - UDim2.fromOffset(0, CALLOUT_RISE * 0.8),
			GroupTransparency = 1,
		})
		out.Completed:Connect(function()
			if token == bannerToken then
				ui.callout.Visible = false
			end
		end)
		out:Play()
	end)
end

--- The dig's own moment. A crusted find announces NOTHING -- its rarity was on the
--- spot and the haul panel already, and "???" only rehearsed the wash bay's reveal
--- badly. What a dig can say is how big it came out, and only when that is news.
--- A sealed find (no crust to wash) is the exception: it identifies right here, so
--- this is its only reveal and it keeps the full banner.
local function onUnearthed(found)
	Sfx.play("unearth")
	-- The haul landed: play the "Success!" moment where the bar is (renderFrame).
	successAt = os.clock()
	ui.haul.Visible = true
	if found.name then
		showFind(found)
		return
	end
	local mult = found.payload
	local label = if type(mult) == "number" then Payload.calloutFor(mult) else nil
	if label then
		showCallout(label, mult)
	end
end

-- ── Input ───────────────────────────────────────────────────────────

local digYank: any = nil
local yankTake = 0
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
	-- Two takes of the same shovel, alternated, with Sfx's pitch jitter on top: one
	-- sample on a verb mashed this fast is audibly a loop inside a second.
	yankTake = 1 - yankTake
	Sfx.play(if yankTake == 0 then "dig" else "dig2")
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
--- part — it rides this client-only SweepState payload (state.contacts).
--- No longer clarity-gated: every detector colours its wells now (DigService.hintFor).
---
--- Matched by position because the payload deliberately carries no signal id. The
--- tolerance covers the drift between the server's snapshot of the player (which the
--- offsets are measured from) and where the client has walked since. Wells are kept
--- MIN_SIGNAL_GAP apart at spawn (DigService), and the closest contact wins below, so
--- a neighbour's reading cannot bind to the wrong well.
local CONTACT_MATCH_TOLERANCE = 4 -- studs

---
--- Second return: the crack scale of THIS client's reading (Config/Weight.crackScale,
--- off the size its nuke will come up at), or nil when the server sent none.
function Detector.contactRarityAt(worldPosition: Vector3): (string?, number?)
	local origin = state.contactOrigin
	if origin == nil or not state.inStage then
		return nil, nil
	end
	-- THE CLOSEST CONTACT, NOT THE FIRST ONE IN TOLERANCE. Contacts arrive nearest-the-
	-- PLAYER first, so with two signals buried a few studs apart the first match for the
	-- far aura was often its neighbour's contact: both spots lit in the nearer signal's
	-- rarity, and pulling that one "made the other vanish" (it re-lit as its own rarity).
	-- Each contact sits exactly on its own aura (same server snapshot), so closest wins.
	local best: Contact? = nil
	local bestDistSq = CONTACT_MATCH_TOLERANCE * CONTACT_MATCH_TOLERANCE
	for _, contact in state.contacts do
		if contact.rarity ~= nil then
			local dx = (origin.X + contact.dx) - worldPosition.X
			local dz = (origin.Z + contact.dz) - worldPosition.Z
			local distSq = dx * dx + dz * dz
			if distSq <= bestDistSq then
				best = contact
				bestDistSq = distSq
			end
		end
	end
	if best then
		return best.rarity, best.scale
	end
	return nil, nil
end

function Detector.start()
	FieldController = require(script.Parent.FieldController)

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
		-- The point the offsets were measured from, so FieldController can turn each
		-- contact back into a world point and match it to an aura well (contactRarityAt).
		-- The server sends its own snapshot (DigService, `origin`): our root is ahead of
		-- it by the replication lag, which at run speed drifted past the match tolerance
		-- and left a fast player's spots dark. Our root is only the fallback.
		if typeof(payload.origin) == "Vector3" then
			state.contactOrigin = payload.origin
		else
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				state.contactOrigin = root.Position
			end
		end
		state.rarityHint = payload.rarityHint
		state.inRange = payload.inRange == true
		-- Stepping onto a signal with no room for it: the refusal gets a thunk, once
		-- per arrival rather than every tick you stand there.
		if payload.blocked == "full" and state.blocked ~= "full" and payload.hasSignal == true then
			Sfx.play("bagFull")
		end
		state.blocked = payload.blocked
		state.overGrip = payload.overGrip or 0
		state.digProgress = payload.digProgress or 0
		state.depth = payload.depth
		state.stageId = payload.stageId
		state.locked = payload.locked == true
		state.fuse = payload.fuse
		state.fuseArmed = payload.fuseArmed == true
		state.fuseLeft = payload.fuseLeft
		state.fuseWindow = payload.fuseWindow
		state.fuseless = payload.fuseless == true
		state.fuseAt = os.clock()
		-- payload.carrying / payload.capacity are deliberately ignored: the hotbar
		-- (InventoryController, fed by CarryState) is the authority on the bag now,
		-- and two widgets answering "how full am I" from two different remotes is how
		-- they end up disagreeing by a tick. payload.strength / payload.newContacts
		-- too, since the audio cues they fed are gone.
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(onUnearthed)

	-- No banner on ItemIdentified. The wash bay stages its own reveal (WashReveal), and
	-- a blind sale at the trader is named on the receipt -- the banner popping up over
	-- the trader's counter mid-sale read as a random interruption. IndexController still
	-- listens to the same remote for the index write.

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
			setKeyGlyph("HOLD", KEY_TEXT_SIZE_TOUCH)
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			setKeyGlyph("X", KEY_TEXT_SIZE)
		else
			setKeyGlyph("E", KEY_TEXT_SIZE)
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
	-- a press drives the prompt's own hold, and its release ends it. This is the documented
	-- way to trigger a custom prompt, and it hands mouse players a click-to-pick-up that
	-- matches the click-to-yank mash. Keyboard and gamepad never touch this path.
	local HOLD_INPUTS = {
		[Enum.UserInputType.MouseButton1] = true,
		[Enum.UserInputType.Touch] = true,
	}
	-- The press is tracked by its InputObject and released from UserInputService, so a
	-- finger that drifts off the keycap and lifts elsewhere still ends the hold rather
	-- than leaving the prompt held with nothing on it.
	local holdInput: InputObject? = nil
	ui.lockGui.hit.InputBegan:Connect(function(input)
		if HOLD_INPUTS[input.UserInputType] and holdInput == nil then
			holdInput = input
			ui.prompt:InputHoldBegin()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if holdInput ~= nil and (input == holdInput or input.UserInputType == Enum.UserInputType.MouseButton1 and holdInput.UserInputType == Enum.UserInputType.MouseButton1) then
			holdInput = nil
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
	-- now, but the haul bar's smoothing and the pick-up card's idle bob are still
	-- driven off os.clock (not dt), so Heartbeat vs RenderStepped only changes how
	-- often they refresh, never what they show. Left on Heartbeat — moving it buys
	-- nothing.
	-- The magnet's hum for as long as a haul is live. 2D, off our own SweepState;
	-- other players' hauls hum from SfxController off the Hauling attribute.
	local haulHum = Sfx.loop("haulHum")
	RunService.Heartbeat:Connect(function(dt)
		renderFrame(dt)
		if haulHum then
			haulHum:set(state.locked)
		end
	end)

	renderState()
end

return Detector
