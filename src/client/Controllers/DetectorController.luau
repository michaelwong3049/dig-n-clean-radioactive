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
local Items = require(Shared.Config.Items)
local Tuning = require(Shared.Config.Tuning)
local Stages = require(Shared.Config.Stages)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local HaulShaft = require(script.Parent.Parent.HaulShaft)
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
local KEY_TEXT_SIZE = 26
local KEY_TEXT_SIZE_TOUCH = 15
-- Tracked by hand -- Roblox has no letter-spacing. See the label in buildLockPromptGui.
local ACTION_TEXT = "P I C K  U P"

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
local YANK_KICK_SCALE = 0.05 -- how far REEL IN presses in at the peak of a kick
-- No yank for this long and the soil is winning: the shaft's strain judder gets harder.
local SHAFT_IDLE_SECONDS = 0.2

-- ── The haul widget's interior ──────────────────────────────────────────────────
-- ALL DERIVED FROM Dock.HAULPANEL_SIZE, never re-hardcoded against it.
--
-- THERE IS NO PANEL BEHIND ANY OF THIS. The widget is a transparent container that
-- only exists to be shown and hidden as a unit; each piece carries itself.
--
-- TWO COLUMNS. On the right, the soil shaft (HaulShaft): a cut-away of the ground with
-- the nuke hauled up it on the magnet's cable -- the nuke's height IS the progress, so
-- there is no bar. Every haul starts on the shaft's floor; the ruler beside it is
-- scaled to that nuke's own burial depth. REEL IN sits under the shaft's foot. On the left, the readout,
-- right-aligned against the shaft: what you hooked (rarity + odds), then the metres
-- still to come up, then the way out level with REEL IN, as far from it as the row
-- allows because hitting the wrong one ends the haul.
local SHAFT_WIDTH = HaulShaft.WIDTH
local SHAFT_STROKE = UIKit.Stroke.normal -- HaulShaft's frame, drawn outside its box
local HAULBUTTON_HEIGHT = 46
local HAULBUTTON_GAP = 7 -- the shaft frame's foot -> REEL IN
local HAULBUTTON_TEXT = 20
local SHAFT_X = Dock.HAULPANEL_SIZE.X.Offset - SHAFT_STROKE - SHAFT_WIDTH
local SHAFT_HEIGHT = Dock.HAULPANEL_SIZE.Y.Offset - HAULBUTTON_HEIGHT - HAULBUTTON_GAP - 2 * SHAFT_STROKE
local HAULBUTTON_Y = Dock.HAULPANEL_SIZE.Y.Offset - HAULBUTTON_HEIGHT

-- The readout column: everything left of the shaft, less a gap. It needs the room for
-- "LEGENDARY" at title weight -- the longest rarity in Rarity.ORDER, and the one thing
-- here that would clip rather than merely look cramped.
local READOUT_GAP = 14
local READOUT_WIDTH = SHAFT_X - SHAFT_STROKE - READOUT_GAP
local READOUT_TOP = 96 -- the rarity word's row; everything else hangs below it
local METRES_TEXT = 50 -- the "1.9 m" headline: the number being watched
-- "%.1f" metres, the unit at half size. RichText, so the label is built without the
-- kit's sibling drop shadow (which would print the tags).
local METRES_FORMAT = '%.1f<font size="24">m</font>'

-- How fast the shaft's nuke chases the server's value (1/seconds). Smoothed rather
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
	-- only to crack the soil round the nuke in the haul shaft as the over-tier grind
	-- steepens -- it never
	-- blocks a haul and never becomes a status message.
	overGrip = 0,
	digProgress = 0,
	-- The locked signal's burial depth in studs (server-sent only while locked), and
	-- the stage it is in: the soil shaft draws the nuke at its true depth, in that
	-- stage's soil.
	depth = nil :: number?,
	stageId = nil :: number?,
	-- Committed to a signal and rooted in place. The server is the authority on this;
	-- the client never decides it is locked on its own, because being locked is what
	-- takes the player's movement away.
	locked = false,
}

local ui = {}
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
	root.Parent = adornee
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
	keycapFill.BackgroundColor3 = COLOR.scope
	keycapFill.BackgroundTransparency = 1
	keycapFill.BorderSizePixel = 0
	keycapFill.ZIndex = 2
	keycapFill.Parent = keycap

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = UIKit.Font.title
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
	-- holds against bright ground now there is no panel behind it.
	--
	-- TRACKED CAPS BY HAND. Roblox TextLabels have no letter-spacing property, and at
	-- this size bold caps set solid read as one block rather than as a word -- the
	-- spaces ARE the tracking. Two spaces between the words so the word gap still beats
	-- the letter gap.
	local action = UIKit.label(card, {
		name = "Action",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.fromScale(0.5, 1),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.title,
		textSize = 16,
		color = COLOR.scope,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
	})
	action.Text = ACTION_TEXT
	action.TextTransparency = 1

	-- UIKit.label hangs a black outline stroke on the label and, for a `title` font, a
	-- drop-shadow TWIN beside it. Neither fades with TextTransparency, so both have to
	-- be fetched and driven explicitly -- without this the prompt hides and leaves a
	-- black ghost of the word hanging over the spot.
	local actionStroke = action:FindFirstChildOfClass("UIStroke")
	local actionShadow = card:FindFirstChild(action.Name .. "Shadow")

	-- The billboard is the touch (and mouse) target; see the header. Transparent,
	-- full-bleed, on top, and OUTSIDE `card` so the bounce never shifts it. It stays the
	-- size of the whole billboard even though the visible prompt no longer fills it --
	-- a lone keycap is a small target on a phone, and the slack around it is deliberate.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
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
		{ keycapFill, "BackgroundTransparency", 0.2 },
		{ keyLabel, "TextTransparency", 0 },
		{ keyStroke, "Transparency", 0 },
		{ action, "TextTransparency", 0 },
	}
	if actionStroke then
		table.insert(fades, { actionStroke, "Transparency", 0 })
	end
	if actionShadow and actionShadow:IsA("TextLabel") then
		table.insert(fades, { actionShadow, "TextTransparency", UIKit.TextShadow.transparency })
	end

	return {
		root = root,
		card = card,
		scale = scale,
		keycap = keycap,
		stroke = stroke,
		keycapFill = keycapFill,
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
	-- fill, no corner, no stroke -- it exists only to place the shaft and its readout as
	-- a unit and to be shown and hidden in one line.
	local haul = Instance.new("Frame")
	haul.Name = "HaulPanel"
	haul.Size = Dock.HAULPANEL_SIZE
	haul.AnchorPoint = Vector2.new(0, 1)
	haul.BackgroundTransparency = 1
	haul.BorderSizePixel = 0
	haul.Visible = false
	haul.Parent = canvas
	ui.haul = haul

	-- LOW AND JUST RIGHT OF CENTRE. Not centred -- that put it straight over the item
	-- climbing out of the soil, the one thing a haul is for looking at -- and not in the
	-- far corner either, which put the reading a long way from where the player is
	-- looking. Its left edge sits Dock.HAULPANEL_CENTRE_GAP right of screen centre; on a
	-- screen too narrow for that it slides left only as far as it must to stop short of
	-- the Index/Shop tiles (Dock.HAULPANEL_RIGHT). Re-placed on every canvas resize,
	-- because the design width moves with both the window and the HUD scale.
	local function placeHaul()
		local width = canvas.AbsoluteSize.X / UIKit.canvasScale(canvas)
		local nearCentre = width / 2 + Dock.HAULPANEL_CENTRE_GAP
		local clearOfTiles = width - Dock.HAULPANEL_RIGHT - Dock.HAULPANEL_SIZE.X.Offset
		haul.Position = UDim2.new(0, math.min(nearCentre, clearOfTiles), 1, -Dock.HAULPANEL_BOTTOM)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeHaul)
	placeHaul()

	-- THE SOIL SHAFT: the picture of the haul. The nuke climbs it on the magnet's cable
	-- from the floor to the grass, so how high it is IS the progress (HaulShaft's
	-- header). renderState paints it in the stage's soil and the signal's colour and
	-- scales its ruler to the nuke's depth; renderFrame moves the nuke every frame.
	ui.shaft = HaulShaft.build(haul, UDim2.fromOffset(SHAFT_X, SHAFT_STROKE), SHAFT_HEIGHT)

	-- REEL IN, UNDER THE SHAFT'S FOOT. A real button and not a key hint because a phone
	-- has no E key -- without a tappable control here the entire second beat would be
	-- keyboard-only. A near-opaque plate, because over open ground a translucent fill
	-- puts the verb on grass. Its outline carries the signal's colour (renderState), in
	-- step with the band on the nuke.
	local haulButton, haulButtonStroke = UIKit.button(haul, {
		name = "HaulButton",
		position = UDim2.fromOffset(SHAFT_X - SHAFT_STROKE, HAULBUTTON_Y),
		size = UDim2.fromOffset(SHAFT_WIDTH + 2 * SHAFT_STROKE, HAULBUTTON_HEIGHT),
		font = UIKit.Font.title,
		textSize = HAULBUTTON_TEXT,
		color = COLOR.text,
		fillColor = COLOR.panel,
		fillTransparency = 0.05,
		strokeColor = COLOR.scope,
		strokeThickness = UIKit.Stroke.normal,
		cornerRadius = UDim.new(0, 10),
		text = "",
		shadow = false,
	})
	ui.haulButton = haulButton
	ui.haulButtonStroke = haulButtonStroke
	-- The kick (renderFrame) presses the plate in through this, rather than resizing it.
	local haulKick = Instance.new("UIScale")
	haulKick.Parent = haulButton
	ui.haulKick = haulKick

	-- Keycap + verb, centred as one row on the plate. Nothing in the row is Active, so a
	-- click anywhere on the plate still lands on the button. The keycap only shows where
	-- there is a keyboard to press it on; a touch player just taps the plate.
	local reelRow = Instance.new("Frame")
	reelRow.Name = "Row"
	reelRow.Size = UDim2.fromScale(1, 1)
	reelRow.BackgroundTransparency = 1
	reelRow.Parent = haulButton
	local reelLayout = Instance.new("UIListLayout")
	reelLayout.FillDirection = Enum.FillDirection.Horizontal
	reelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	reelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	reelLayout.Padding = UDim.new(0, 10)
	reelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	reelLayout.Parent = reelRow

	local reelKey = Instance.new("Frame")
	reelKey.Name = "Keycap"
	reelKey.Size = UDim2.fromOffset(30, 30)
	reelKey.BackgroundColor3 = COLOR.text
	reelKey.BorderSizePixel = 0
	reelKey.LayoutOrder = 1
	reelKey.Visible = UserInputService.KeyboardEnabled
	reelKey.Parent = reelRow
	local reelKeyCorner = Instance.new("UICorner")
	reelKeyCorner.CornerRadius = UDim.new(0, 7)
	reelKeyCorner.Parent = reelKey
	UIKit.label(reelKey, {
		name = "Key",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.title,
		textSize = 17,
		color = COLOR.panel,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		text = "E",
	})
	-- NO TEXT OUTLINE on the verb: it sits on its own near-opaque plate, and an outline
	-- there only fattens the glyphs into each other.
	local reelVerb = UIKit.label(reelRow, {
		name = "Verb",
		size = UDim2.fromOffset(0, 30),
		font = UIKit.Font.title,
		textSize = HAULBUTTON_TEXT,
		color = COLOR.text,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		text = "REEL IN",
	})
	reelVerb.AutomaticSize = Enum.AutomaticSize.X
	reelVerb.LayoutOrder = 2

	-- RELEASE HAS TO BE VISIBLE. Locking roots the character, so a player who cannot
	-- find the way out is stuck standing in a field. It is a real button rather than
	-- only a key hint for the same reason REEL IN is: on touch there is no Q. Level with
	-- REEL IN but at the far end of the row, right-aligned under the readout -- the two
	-- are the only controls here and hitting the wrong one ends the haul.
	--
	-- No outline and no fill: this is a quiet way out, not a second call to action. It
	-- has nothing behind it, so it takes a text stroke to stay legible over bright ground.
	local releaseButton = UIKit.button(haul, {
		name = "ReleaseButton",
		position = UDim2.fromOffset(0, HAULBUTTON_Y),
		size = UDim2.fromOffset(READOUT_WIDTH, HAULBUTTON_HEIGHT),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = COLOR.text,
		fillColor = COLOR.panel,
		fillTransparency = 1,
		strokeThickness = 0,
		cornerRadius = UIKit.Radius.button,
		text = "Q  to release",
	})
	releaseButton.TextXAlignment = Enum.TextXAlignment.Right
	releaseButton.TextStrokeTransparency = 0.2
	ui.releaseButton = releaseButton

	-- THE READOUT, right-aligned against the shaft: what the detector reads about the
	-- thing you locked onto, then how far it still has to come. The rarity word is the
	-- headline and carries the accent tint (in step with the nuke's band and REEL IN's
	-- outline), the odds sit under it, and below them the metres left -- the number
	-- actually being watched, so it is the big one. All of it lands on any detector
	-- (DigService.hintFor is not clarity-gated), and all of it takes the kit's hard
	-- outline, because with no panel behind it this text can end up over sunlit sludge.
	ui.haulTitle = UIKit.label(haul, {
		name = "Title",
		position = UDim2.fromOffset(0, READOUT_TOP),
		size = UDim2.fromOffset(READOUT_WIDTH, 30),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.title,
		color = COLOR.scope,
		xAlign = Enum.TextXAlignment.Right,
	})

	ui.haulOdds = UIKit.label(haul, {
		name = "Odds",
		position = UDim2.fromOffset(0, READOUT_TOP + 32),
		size = UDim2.fromOffset(READOUT_WIDTH, 22),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- A question mark, IN THE RARITY WORD'S OWN SLOT. You committed to a lump in the
	-- dirt; whether you get to know what it is is the detector's job, not this widget's.
	-- Hidden the moment the rarity resolves -- the two share one rectangle, and
	-- "LEGENDARY" next to a "?" reads as a bug.
	ui.haulQuestion = UIKit.label(haul, {
		name = "HaulQuestion",
		position = UDim2.fromOffset(0, READOUT_TOP),
		size = UDim2.fromOffset(READOUT_WIDTH, 30),
		font = UIKit.Font.title,
		textSize = 30,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "?",
	})

	-- The metres still to come up (renderFrame, every frame, off the smoothed progress so
	-- it falls in step with the nuke rather than in 10 Hz steps). The depth is known
	-- whether or not the rarity is, so this shows under the "?" too.
	ui.haulMetres = UIKit.label(haul, {
		name = "Metres",
		position = UDim2.fromOffset(0, READOUT_TOP + 80),
		size = UDim2.fromOffset(READOUT_WIDTH, METRES_TEXT),
		font = UIKit.Font.hero,
		textSize = METRES_TEXT,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Right,
		shadow = false,
	})
	ui.haulMetres.RichText = true

	UIKit.label(haul, {
		name = "MetresCaption",
		position = UDim2.fromOffset(0, READOUT_TOP + 84 + METRES_TEXT),
		size = UDim2.fromOffset(READOUT_WIDTH, 20),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Right,
		shadow = false,
		text = "to the surface",
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
	ui.haulKick.Scale = 1 - kick * YANK_KICK_SCALE

	if state.locked then
		-- THE NUKE IS THE BAR. Every haul starts it on the shaft's floor and it climbs
		-- the full height on progress alone; the depth only sets the ruler's scale
		-- (renderState) and the metres still to come up, printed beside it.
		local climbed = math.clamp(shownProgress, 0, 1)
		local toGo = if state.depth then state.depth * (1 - climbed) / Stages.STUDS_PER_METRE else nil
		HaulShaft.step(ui.shaft, {
			progress = climbed,
			strain = state.overGrip,
			kick = kick,
			idle = sinceYank > SHAFT_IDLE_SECONDS and climbed > 0,
			now = os.clock(),
		})
		ui.haulMetres.Text = if toGo then string.format(METRES_FORMAT, toGo) else ""
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
--- "HOLD" is a whole word at 15px while "E"/"X" are single glyphs at 26 — one thickness
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
	ui.prompt.ObjectText = if state.rarityHint then string.upper(state.rarityHint) else "Buried Signal"
	ui.lockGui.action.TextColor3 = accent
	ui.lockGui.stroke.Color = accent
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
		-- THE SIGNAL'S COLOUR, in two places that move together: the band and glow on
		-- the nuke in the shaft, and REEL IN's outline. Scope blue only in the brief
		-- frame before the rarity resolves -- the "?" beside the shaft is that state at
		-- rest; this is it in colour. The soil is the stage's own, and the ruler down the
		-- shaft is scaled to this nuke's burial depth (both no-ops once set, so safe on
		-- every tick).
		local accent = signalColor()
		ui.haulButtonStroke.Color = accent
		HaulShaft.setAccent(ui.shaft, accent)
		if state.stageId then
			HaulShaft.paint(ui.shaft, state.stageId)
		end
		HaulShaft.setDepth(ui.shaft, if state.depth then state.depth / Stages.STUDS_PER_METRE else nil)

		-- The readout spells out what the colour only implies: the rarity word
		-- (state.rarityHint) and the "1 in N" odds (state.oddsHint), both on any
		-- detector now -- exactly what DigService.hintFor sent. Two labels stacked
		-- beside the shaft rather than one joined line, so a long rarity and a
		-- six-figure odds never have to share a row this narrow.
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
		-- weak -- the grind says it. The shaft says it too, without words: the soil
		-- around the nuke cracks and glows and the nuke judders, harder the further the
		-- soil outclasses the magnet (renderFrame hands state.overGrip to HaulShaft.step).
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

--- What the banner says over a find nobody has identified yet. It is not a placeholder
--- for a name the client is withholding -- the client genuinely does not have one, and
--- will not until the crust comes off (Services/IdentifyService).
local UNKNOWN_NAME = "???"
local UNKNOWN_FLAVOR = "caked in irradiated slag \u{2014} wash it to find out what it is"

--- ONE BANNER, TWO MOMENTS. The dig fires it with a rarity and no name; the wash bay
--- fires it again, on the same item, with the name it turned out to have. Sharing the
--- renderer is what keeps them feeling like two halves of one event rather than two
--- unrelated pieces of UI, and `found.name` being nil is the only thing that separates
--- them here.
local function showFind(found, header: string?)
	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else COLOR.text

	local modifier = if found.modifier == "None" or found.modifier == nil then "" else found.modifier .. " "
	local heft = if type(found.weight) == "number" then `  \u{00B7}  {formatWeight(found.weight)}` else ""
	local prefix = if header then header .. `  \u{00B7}  ` else ""
	ui.bannerRarity.Text = prefix .. string.upper(modifier .. found.rarity) .. heft
	ui.bannerRarity.TextColor3 = colour
	ui.bannerName.Text = found.name or UNKNOWN_NAME
	ui.bannerFlavor.Text = found.flavor or UNKNOWN_FLAVOR
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
--- part — it rides this client-only SweepState payload (state.contacts).
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
		state.depth = payload.depth
		state.stageId = payload.stageId
		state.locked = payload.locked == true
		-- payload.carrying / payload.capacity are deliberately ignored: the hotbar
		-- (InventoryController, fed by CarryState) is the authority on the bag now,
		-- and two widgets answering "how full am I" from two different remotes is how
		-- they end up disagreeing by a tick. payload.strength / payload.newContacts
		-- too, since the audio cues they fed are gone.
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(function(found)
		showFind(found)
	end)

	-- THE OTHER HALF OF THE SAME BANNER. Fired from the wash bay once the last chunk of
	-- crust is off (or from the trader, when a find is sold blind and named on its way
	-- out) -- the "so THAT'S what it was" beat the dig no longer gets to have.
	Net.get("ItemIdentified").OnClientEvent:Connect(function(found)
		showFind(found, if found.firstFind then "NEW FIND" else "IDENTIFIED")
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
	-- now, but the haul bar's smoothing and the pick-up card's idle bob are still
	-- driven off os.clock (not dt), so Heartbeat vs RenderStepped only changes how
	-- often they refresh, never what they show. Left on Heartbeat — moving it buys
	-- nothing.
	RunService.Heartbeat:Connect(function(dt)
		renderFrame(dt)
	end)

	renderState()
end

return Detector
